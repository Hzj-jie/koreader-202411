describe("AnnotationSync Core Integration", function()
  local ReaderUI, UIManager, SyncService, Geom
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util, annotations_mod
  local readerui, sync_instance, real_sync
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_integration_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    Geom = require("ui/geometry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    real_sync = SyncService.sync
    json = require("json")
    util = require("util")
    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")

    highlight_db = require("plugins/AnnotationSync.koplugin/highlight_db")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server", type = "webdav" })
    )

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    require("ui/widget/imageviewer").new = _G.old_ImageViewer_new
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
  end)

  before_each(function()
    UIManager:show(readerui)
    fastforward_ui_events()
    readerui.annotation.annotations = {}
    sync_instance.settings.last_sync = "Never"
    sync_instance.settings.use_filename = true
    sync_instance.manager:cleanSyncFile(readerui.document)
    os.remove(sync_instance.manager:changedDocumentsFile())

    test_utils.mock_sync_service(SyncService)
  end)

  local function create_ann_from_db(index, note, datetime)
    local entry = highlight_db[index]
    local ann = {
      page = entry.p0,
      pos0 = entry.p0,
      pos1 = entry.p1,
      text = entry.text,
      chapter = "Test Chapter",
      datetime = datetime or "2026-01-01 12:00:00",
      note = note,
    }
    return ann
  end

  describe("Tracking & Persistence", function()
    it("tracks highlights and persists changed state", function()
      readerui.rolling:onGotoPage(3)
      fastforward_ui_events()
      test_utils.emulate_highlight(readerui, highlight_db[1])

      local count, docs = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(1, count)
      assert.is_true(docs[readerui.document.file])

      sync_instance:manualSync()
      assert.is_false(sync_instance.manager:hasPendingChangedDocuments())
    end)

    it("manualSync remains synchronous and does NOT use Trapper", function()
      local Trapper = require("ui/trapper")
      local wrap_called = false
      local old_wrap = Trapper.wrap
      Trapper.wrap = function(this, func)
        wrap_called = true
        func()
      end

      sync_instance:manualSync()

      assert.is_false(wrap_called)
      Trapper.wrap = old_wrap
    end)

    it("handles first sync of an empty book gracefully", function()
      -- Ensure no previous files exist
      sync_instance.manager:cleanSyncFile(readerui.document)

      -- Sync an empty book
      sync_instance:manualSync()

      -- Should succeed and update metadata
      assert.is_not_equal("Never", sync_instance.settings.last_sync)
      assert.is_equal(0, #readerui.annotation.annotations)
    end)

    it("handles first sync with local annotations gracefully", function()
      -- 1. Ensure no previous files exist
      sync_instance.manager:cleanSyncFile(readerui.document)

      -- 2. Create some local annotations
      test_utils.emulate_highlight(readerui, highlight_db[1])
      assert.is_equal(1, #readerui.annotation.annotations)

      -- 3. Sync (First time)
      sync_instance:manualSync()

      -- 4. Should succeed, mark as clean, and have 1 annotation
      assert.is_not_equal("Never", sync_instance.settings.last_sync)
      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_false(sync_instance.manager:hasPendingChangedDocuments())
    end)
  end)

  describe("Bidirectional Merge & Conflicts", function()
    it("merges disjoint local and remote additions", function()
      test_utils.emulate_highlight(readerui, highlight_db[1])

      local ann2 = create_ann_from_db(2)
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_disjoint.json",
        { ann2 }
      )

      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(success)
        end
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)

      assert.is_equal(2, #readerui.annotation.annotations)
    end)

    it("resolves conflicts using timestamps (latest wins)", function()
      local ann_l =
        create_ann_from_db(1, "Local Newer", "2026-02-02 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r =
        create_ann_from_db(1, "Remote Older", "2026-02-01 12:00:00")
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_conflict.json",
        { ann_r }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ ann_r }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(success)
        end
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)
      assert.is_equal("Local Newer", readerui.annotation.annotations[1].note)
    end)

    it("resurrects zombie if modification is newer than deletion", function()
      -- Remote has deletion, but local has a NEWER modification
      local ann_l = create_ann_from_db(1, "Revived", "2026-02-05 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r = create_ann_from_db(1)
      ann_r.deleted = true
      ann_r.datetime_updated = "2026-02-01 12:00:00"

      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_zombie.json",
        { ann_r }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ ann_r }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(success)
        end
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)
      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_equal("Revived", readerui.annotation.annotations[1].note)
    end)
  end)

  describe("Deletion", function()
    it("synchronizes deletions bidirectionally", function()
      local ann = create_ann_from_db(1)
      table.insert(readerui.annotation.annotations, ann)

      local ann_del = util.tableDeepCopy(ann)
      ann_del.deleted = true
      ann_del.datetime_updated = "2026-02-02 12:00:00"

      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_del.json",
        { ann_del }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ ann }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(success)
        end
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)
      assert.is_equal(0, #readerui.annotation.annotations)
    end)

    it(
      "should return nil from sync_callback when remote file is missing and local file is empty",
      function()
        local local_path =
          test_utils.write_mock_json(test_data_dir, "empty_local.json", {})
        local last_sync_path =
          test_utils.write_mock_json(test_data_dir, "empty_last.json", {})
        local res =
          annotations_mod.sync_callback(local_path, last_sync_path, nil, false)
        assert.is_nil(res)
      end
    )

    it(
      "verifies that Dropbox 'path not found' error is handled gracefully",
      function()
        readerui.annotation.annotations = {
          { page = 1, pos0 = "p0", pos1 = "p1", text = "hello" },
        }
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local dropbox_error = {
          error_summary = "path/not_found/.",
          error = {
            [".tag"] = "path",
            path = { [".tag"] = "not_found" },
          },
        }

        local old_sync = SyncService.sync
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          local income_file = local_path .. ".temp"
          local f = io.open(income_file, "w")
          f:write(json.encode(dropbox_error))
          f:close()

          local cached_file = local_path .. ".sync"
          if not io.open(cached_file, "r") then
            local fc = io.open(cached_file, "w")
            fc:write("{}")
            fc:close()
          end

          local success = callback(local_path, cached_file, income_file, 409)
          os.remove(income_file)
          if finish_cb then
            finish_cb(success)
          end
          return success
        end

        local success =
          sync_instance.manager:syncDocument(readerui.document, true)

        assert.is_true(
          success,
          "Sync should succeed by treating Dropbox path/not_found as empty state"
        )

        SyncService.sync = old_sync
      end
    )

    it("verifies sidecar directory creation for new books", function()
      local file = readerui.document.file
      sync_instance.manager:addToChangedDocumentsFile(file)
      local sdr_dir = require("frontend/docsettings"):getSidecarDir(file)
      os.execute("rm -rf " .. sdr_dir)

      local lfs = require("libs/libkoreader-lfs")
      assert.is_nil(
        lfs.attributes(sdr_dir),
        "Sidecar directory should be missing for test"
      )

      local old_sync = SyncService.sync
      SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, local_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(success)
        end
        return true
      end

      sync_instance.manager:syncAllChangedDocuments()

      assert.is_not_nil(
        lfs.attributes(sdr_dir),
        "Sidecar directory should have been created automatically"
      )

      SyncService.sync = old_sync
      local count, _ = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(0, count, "Document should have been successfully synced")
    end)
  end)

  describe(
    "End-to-end sync with real SyncService.sync and mocked dropboxapi (D1-D3)",
    function()
      local ffiutil = require("ffi/util")
      local DocSettings = require("frontend/docsettings")
      local remote_store, upload_code, uploads, shown
      local old_show, old_sync

      local function basename(p)
        return p:match("([^/]+)$")
      end

      local function hl(n, text, ts)
        local p0 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().0"
        local p1 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().20"
        return {
          page = p0,
          pos0 = p0,
          pos1 = p1,
          text = text,
          datetime = ts,
          drawer = "lighten",
          color = "yellow",
        }
      end

      local function new_doc(tag)
        local doc = test_data_dir .. "/" .. tag .. ".epub"
        ffiutil.copyFile("spec/front/unit/data/juliet.epub", doc)
        return doc, sync_instance.manager:_getAnnotationFilename(doc)
      end

      local function is_pending(file)
        local _, docs = sync_instance.manager:getPendingChangedDocuments()
        return docs and docs[file] == true
      end

      before_each(function()
        remote_store, upload_code, uploads, shown = {}, 200, {}, {}
        old_show = UIManager.show
        old_sync = SyncService.sync
        SyncService.sync = real_sync

        package.loaded["apps/cloudstorage/dropboxapi"] = {
          downloadFile = function(_, url, _token, dest)
            local content = remote_store[basename(url)]
            if not content then
              return 409
            end
            util.writeToFile(content, dest)
            return 200, "etag-1"
          end,
          uploadFile = function(
            _,
            _url_base,
            _token,
            file_path,
            _etag,
            _overwrite
          )
            if upload_code ~= 200 then
              return upload_code
            end
            local f = io.open(file_path, "r")
            local content = f:read("*a")
            f:close()
            remote_store[basename(file_path)] = content
            table.insert(uploads, basename(file_path))
            return 200
          end,
        }

        UIManager.show = function(self, w, ...)
          if type(w) == "table" and type(w.text) == "string" then
            table.insert(shown, w.text)
            return
          end
          return old_show(self, w, ...)
        end

        sync_instance.settings.sync_server = {
          type = "dropbox",
          url = "/koreader",
          password = "token",
          address = "",
        }
      end)

      after_each(function()
        UIManager.show = old_show
        SyncService.sync = old_sync
        package.loaded["apps/cloudstorage/dropboxapi"] = nil
      end)

      it(
        "Case 22: manual sync, upload returns 500 -> syncDocument returns false, doc stays pending, merge base unchanged, message shown (D1)",
        function()
          local doc, name = new_doc("d1")
          local A = hl(1, "A_local", "2026-01-01 10:00:00")
          local R = hl(2, "R_remote", "2026-01-02 10:00:00")
          local ds = DocSettings:open(doc)
          ds:save("annotations", { A })
          ds:flush()
          local base = json.encode({ A })
          util.writeToFile(base, sync_instance.manager:getSyncCachePath(doc))
          remote_store[name] = json.encode({ A, R })
          sync_instance.manager:addToChangedDocumentsFile(doc)
          upload_code = 500

          local ret = sync_instance.manager:syncDocument(doc, true)
          local f = io.open(sync_instance.manager:getSyncCachePath(doc), "r")
          local base_after = f:read("*a")
          f:close()

          assert.is_false(ret)
          assert.is_true(is_pending(doc))
          assert.are.equal(base, base_after)
          assert.is_true(#shown > 0)
        end
      )

      it(
        "Case 23: manual sync with nothing to upload -> success, no longer pending, 0 uploads, no message (D2)",
        function()
          local doc, name = new_doc("d2")
          sync_instance.manager:addToChangedDocumentsFile(doc)

          -- D2a: remote returns 409
          local ret = sync_instance.manager:syncDocument(doc, true)
          assert.is_true(ret)
          assert.is_false(is_pending(doc))
          assert.are.equal(0, #uploads)
          assert.are.equal(0, #shown)

          -- D2b: remote returns empty table {}
          remote_store[name] = "{}"
          sync_instance.manager:addToChangedDocumentsFile(doc)
          ret = sync_instance.manager:syncDocument(doc, true)
          assert.is_true(ret)
          assert.is_false(is_pending(doc))
          assert.are.equal(0, #uploads)
          assert.are.equal(0, #shown)
        end
      )

      it(
        "Case 24: remote file isn't JSON -> false, stays pending, generic message (D3)",
        function()
          local doc, name = new_doc("d3")
          local A = hl(1, "A_local", "2026-01-01 10:00:00")
          local ds = DocSettings:open(doc)
          ds:save("annotations", { A })
          ds:flush()
          remote_store[name] = "<html>500 Internal Server Error</html>"
          sync_instance.manager:addToChangedDocumentsFile(doc)

          local ret = sync_instance.manager:syncDocument(doc, true)
          assert.is_false(ret)
          assert.is_true(is_pending(doc))
          assert.is_true(#shown > 0)
          assert.are.equal(0, #uploads)
        end
      )
    end
  )

  describe("Annotation Ordering and Settings Persistence (N12 & N13)", function()
    it("write_annotations_json does not sort stored_annotations in-place (N13)", function()
      local ann1 = {
        page = "/1/4/2/1[p1]/text().2407",
        pos0 = "/1/4/2/1[p1]/text().2407",
        pos1 = "/1/4/2/1[p1]/text().2500",
        datetime = "2026-01-01 10:00:00",
      }
      local ann2 = {
        page = "/1/4/2/1[p1]/strong/text().0",
        pos0 = "/1/4/2/1[p1]/strong/text().0",
        pos1 = "/1/4/2/1[p1]/strong/text().10",
        datetime = "2026-01-01 10:00:00",
      }
      local stored = { ann1, ann2 }
      local path = annotations_mod.write_annotations_json(
        stored,
        test_data_dir,
        "test_n13_order.json"
      )
      finally(function()
        if path then
          os.remove(path)
        end
      end)
      assert.truthy(path)
      assert.are_equal(ann1, stored[1])
      assert.are_equal(ann2, stored[2])
    end)

    it("applySyncedAnnotations updates active doc_settings and keeps table reference (N12)", function()
      local xp = readerui.document:getPageXPointer(1)
      local ann = {
        page = xp,
        pos0 = xp,
        pos1 = xp,
        text = "Open book synced",
        datetime = "2026-01-01 12:00:00",
        drawer = true,
      }
      local merged = { ann }
      sync_instance:applySyncedAnnotations(readerui.document, merged)

      assert.are_equal(merged, readerui.annotation.annotations)
      assert.are_equal(merged, readerui.doc_settings.data.annotations)
      assert.are_equal(merged, readerui.doc_settings:readTableRef("annotations"))
    end)

    it("applySyncedAnnotations on open book sorts using core sortItems (N13)", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp3 = readerui.document:getPageXPointer(3)
      local ann_p3 = {
        page = xp3,
        pos0 = xp3,
        pos1 = xp3,
        datetime = "2026-01-01 10:00:00",
        drawer = true,
      }
      local ann_p1 = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        datetime = "2026-01-01 10:00:00",
        drawer = true,
      }
      local merged = { ann_p3, ann_p1 }
      local sort_called = false
      local old_sortItems = readerui.annotation.sortItems
      readerui.annotation.sortItems = function(self, items)
        sort_called = true
        old_sortItems(self, items)
      end
      finally(function()
        readerui.annotation.sortItems = old_sortItems
      end)

      sync_instance:applySyncedAnnotations(readerui.document, merged)
      assert.is_true(sort_called)
      assert.are_equal(ann_p1, readerui.annotation.annotations[1])
      assert.are_equal(ann_p3, readerui.annotation.annotations[2])
    end)

    it("applySyncedAnnotations on closed book marks annotations_externally_modified (N13)", function()
      local closed_file = test_data_dir .. "/closed_doc.epub"
      local DocSettings = require("docsettings")
      local ds = DocSettings:open(closed_file)
      ds:save("annotations", {})
      ds:flush()
      finally(function()
        os.remove(closed_file)
        local sdr = test_data_dir .. "/closed_doc.sdr"
        os.execute("rm -rf " .. sdr)
      end)

      local ann = {
        page = 1,
        pos0 = "p0",
        pos1 = "p1",
        text = "Closed doc note",
        datetime = "2026-01-01 10:00:00",
      }
      sync_instance:applySyncedAnnotations({ file = closed_file }, { ann })

      local reloaded_ds = DocSettings:open(closed_file)
      assert.is_true(reloaded_ds:isTrue("annotations_externally_modified"))
      local anns = reloaded_ds:readTable("annotations")
      assert.are_equal(1, #anns)
      assert.are_equal("Closed doc note", anns[1].text)
    end)
  end)
end)
