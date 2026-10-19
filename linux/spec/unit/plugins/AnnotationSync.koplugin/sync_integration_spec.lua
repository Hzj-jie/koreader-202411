describe("AnnotationSync Core Integration", function()
  local UIManager, SyncService, gettext
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util, utils, annotations_mod
  local readerui, sync_instance, real_sync, restore_jobs
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_integration_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    real_sync = SyncService.sync
    gettext = require("gettext")
    json = require("json")
    util = require("util")
    utils = require("plugins/AnnotationSync.koplugin/utils")
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
    sync_instance.manager.running = nil
    sync_instance.manager.requested = {}
    sync_instance.manager.last_sync_time = {}
    os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))
    os.remove(sync_instance.manager:changedDocumentsFile())

    test_utils.mock_sync_service(SyncService)
    restore_jobs = test_utils.run_jobs_inline()
  end)

  after_each(function()
    restore_jobs()
  end)

  local function create_ann_from_db(index, note, datetime, datetime_updated)
    local entry = highlight_db[index]
    local ann = {
      drawer = "lighten",
      page = entry.p0,
      pos0 = entry.p0,
      pos1 = entry.p1,
      text = entry.text,
      chapter = "Test Chapter",
      datetime = datetime or "2026-01-01 12:00:00",
      datetime_updated = datetime_updated or datetime or "2026-01-01 12:00:00",
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
      assert.truthy(util.arrayContains(docs, readerui.document.file))

      sync_instance:manualSync()
      sync_instance.manager:dispatchNextSync()
      assert.is_equal(0, (sync_instance.manager:getPendingChangedDocuments()))
    end)

    it("handles first sync of an empty book gracefully", function()
      -- Ensure no previous files exist
      os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))

      -- Sync an empty book
      sync_instance:manualSync()
      sync_instance.manager:dispatchNextSync()

      -- Should succeed and update metadata
      assert.is_not_equal("Never", sync_instance.settings.last_sync)
      assert.is_equal(0, #readerui.annotation.annotations)
    end)

    it("handles first sync with local annotations gracefully", function()
      -- 1. Ensure no previous files exist
      os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))

      -- 2. Create some local annotations
      test_utils.emulate_highlight(readerui, highlight_db[1])
      assert.is_equal(1, #readerui.annotation.annotations)

      -- 3. Sync (First time)
      sync_instance:manualSync()
      sync_instance.manager:dispatchNextSync()

      -- 4. Should succeed, mark as clean, and have 1 annotation
      assert.is_not_equal("Never", sync_instance.settings.last_sync)
      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_equal(0, (sync_instance.manager:getPendingChangedDocuments()))
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
      sync_instance.manager:dispatchNextSync()
      os.remove(income_path)

      assert.is_equal(2, #readerui.annotation.annotations)
    end)

    it("resolves conflicts using timestamps (latest wins)", function()
      local ann_l =
        create_ann_from_db(1, "Local Newer", "2026-01-01 12:00:00", "2026-02-02 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r =
        create_ann_from_db(1, "Remote Older", "2026-01-01 12:00:00", "2026-02-01 12:00:00")
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
      sync_instance.manager:dispatchNextSync()
      os.remove(income_path)
      assert.is_equal("Local Newer", readerui.annotation.annotations[1].note)
    end)

    it("resurrects zombie if modification is newer than deletion", function()
      -- Remote has deletion, but local has a NEWER modification
      local ann_l =
        create_ann_from_db(1, "Revived", "2026-01-01 12:00:00", "2026-02-05 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r = create_ann_from_db(1, nil, "2026-01-01 12:00:00")
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
      sync_instance.manager:dispatchNextSync()
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
      sync_instance.manager:dispatchNextSync()
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
        local res = annotations_mod.sync_callback(
          local_path,
          last_sync_path,
          nil,
          404
        )
        assert.is_nil(res)
      end
    )

    it(
      "verifies that Dropbox 'path not found' error is handled gracefully",
      function()
        readerui.annotation.annotations = {
          {
            drawer = "lighten",
            page = "p0",
            pos0 = "p0",
            pos1 = "p1",
            text = "hello",
          },
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

        sync_instance:manualSync()
        sync_instance.manager:dispatchNextSync()

        assert.is_equal(
          0,
          (sync_instance.manager:getPendingChangedDocuments()),
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
      sync_instance.manager:dispatchNextSync()

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
    "End-to-end sync with real SyncService.sync and mocked dropboxapi",
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
        return not not (docs and util.arrayContains(docs, file))
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
        "manual sync, upload returns 500 -> fails, doc stays pending, merge base unchanged, says it failed",
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

          sync_instance.manager:syncNow(doc)
          sync_instance.manager:dispatchNextSync()
          local f = io.open(sync_instance.manager:getSyncCachePath(doc), "r")
          local base_after = f:read("*a")
          f:close()

          assert.is_true(is_pending(doc))
          assert.are.equal(base, base_after)
          assert.are.same(
            { "Syncing d1.epub in the background", "Failed to sync d1.epub." },
            shown
          )
        end
      )

      it(
        "manual sync with nothing to upload -> success, no longer pending, 0 uploads, says it synced",
        function()
          local doc, name = new_doc("d2")
          sync_instance.manager:addToChangedDocumentsFile(doc)

          -- D2a: remote returns 409
          sync_instance.manager:syncNow(doc)
          sync_instance.manager:dispatchNextSync()
          assert.is_false(is_pending(doc))
          assert.are.equal(0, #uploads)
          assert.are.same(
            { "Syncing d2.epub in the background", "Synced: d2.epub" },
            shown
          )

          -- D2b: remote returns empty table {}
          remote_store[name] = "{}"
          sync_instance.manager:addToChangedDocumentsFile(doc)
          sync_instance.manager:syncNow(doc)
          sync_instance.manager:dispatchNextSync()
          assert.is_false(is_pending(doc))
          assert.are.equal(0, #uploads)
          assert.are.same({
            "Syncing d2.epub in the background",
            "Synced: d2.epub",
            "Syncing d2.epub in the background",
            "Synced: d2.epub",
          }, shown)
        end
      )

      it(
        "remote file isn't JSON -> fails, stays pending, says it failed",
        function()
          local doc, name = new_doc("d3")
          local A = hl(1, "A_local", "2026-01-01 10:00:00")
          local ds = DocSettings:open(doc)
          ds:save("annotations", { A })
          ds:flush()
          remote_store[name] = "<html>500 Internal Server Error</html>"
          sync_instance.manager:addToChangedDocumentsFile(doc)

          sync_instance.manager:syncNow(doc)
          sync_instance.manager:dispatchNextSync()
          assert.is_true(is_pending(doc))
          assert.are.same(
            { "Syncing d3.epub in the background", "Failed to sync d3.epub." },
            shown
          )
          assert.are.equal(0, #uploads)
        end
      )
    end
  )

  describe("Annotation Ordering and Settings Persistence", function()
    it("write_annotations_json does not sort stored_annotations in-place", function()
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

    it("applySyncedAnnotations updates active doc_settings and keeps table reference", function()
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

    it("applySyncedAnnotations on open book sorts using core sortItems", function()
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

    it("background sync waits for tracked dialog to close before applying changes and promoting merge base", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp2 = readerui.document:getPageXPointer(2)

      local A = {
        page = xp2,
        pos0 = xp2,
        pos1 = xp2,
        text = "Highlight A",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      local C = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight C",
        datetime = "2026-01-01 09:00:00",
        drawer = "lighten",
      }

      readerui.annotation.annotations = { A }
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", { A })
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      local cache_path = sync_instance.manager:getSyncCachePath(doc_file)
      util.writeToFile(json.encode({ A }), cache_path)

      local tmp_income = require("datastorage"):getTmpDir() .. "/" .. sync_instance.manager:_getAnnotationFilename(doc_file) .. ".income"
      util.writeToFile(json.encode({ C, A }), tmp_income)
      finally(function()
        os.remove(tmp_income)
        sync_instance.manager.running = nil
      end)

      local widget = require("ui/widget/widget"):new()
      readerui.annotation:trackChangingWidget(widget)

      sync_instance.manager:addToChangedDocumentsFile(doc_file)
      sync_instance.manager:syncNow(doc_file)
      sync_instance.manager:dispatchNextSync()

      -- With dialog open, finished sync does not change the book or merge base yet, and running stays set
      assert.are.equal(1, #readerui.annotation.annotations)
      assert.are.equal("Highlight A", readerui.annotation.annotations[1].text)
      assert.are.equal(1, #utils.read_json(cache_path))
      assert.are.equal(doc_file, sync_instance.manager.running)
      assert.is_nil(sync_instance.manager.last_sync_time[doc_file])

      -- Dialog closes and one tick passes
      widget:onClose()
      fastforward_ui_events()

      -- Merge is applied, base is promoted, and finish() has run
      assert.are.equal(2, #readerui.annotation.annotations)
      local texts = {}
      for _, ann in ipairs(readerui.annotation.annotations) do
        table.insert(texts, ann.text)
      end
      assert.are.same({ "Highlight C", "Highlight A" }, texts)
      assert.are.equal(2, #utils.read_json(cache_path))
      assert.is_nil(sync_instance.manager.running)
      assert.is_not_nil(sync_instance.manager.last_sync_time[doc_file])
    end)

    it("annotation added while apply is queued survives because re-merge reads book when callback runs", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp2 = readerui.document:getPageXPointer(2)
      local xp3 = readerui.document:getPageXPointer(3)

      local A = {
        page = xp2,
        pos0 = xp2,
        pos1 = xp2,
        text = "Highlight A",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      local C = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight C",
        datetime = "2026-01-01 09:00:00",
        drawer = "lighten",
      }

      readerui.annotation.annotations = { A }
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", { A })
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      util.writeToFile(json.encode({ A }), sync_instance.manager:getSyncCachePath(doc_file))

      local tmp_income = require("datastorage"):getTmpDir() .. "/" .. sync_instance.manager:_getAnnotationFilename(doc_file) .. ".income"
      util.writeToFile(json.encode({ C, A }), tmp_income)
      finally(function()
        os.remove(tmp_income)
        sync_instance.manager.running = nil
      end)

      local widget = require("ui/widget/widget"):new()
      readerui.annotation:trackChangingWidget(widget)

      sync_instance.manager:addToChangedDocumentsFile(doc_file)
      sync_instance.manager:syncNow(doc_file)
      sync_instance.manager:dispatchNextSync()

      -- While dialog is open, apply is queued: book still has only A
      assert.are.equal(1, #readerui.annotation.annotations)
      assert.are.equal(doc_file, sync_instance.manager.running)

      -- User adds B while dialog is open and apply is queued
      local B = {
        page = xp3,
        pos0 = xp3,
        pos1 = xp3,
        text = "Highlight B",
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
      }
      table.insert(readerui.annotation.annotations, B)
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", readerui.annotation.annotations)
      readerui.doc_settings:flush()

      widget:onClose()
      fastforward_ui_events()

      local texts = {}
      for _, ann in ipairs(readerui.annotation.annotations) do
        table.insert(texts, ann.text)
      end
      assert.are.same({ "Highlight C", "Highlight A", "Highlight B" }, texts)
      assert.is_nil(sync_instance.manager.running)
    end)

    it("highlight dialog open plus a remote item sorting before: dialog Delete removes the chosen highlight", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp2 = readerui.document:getPageXPointer(2)
      local xp3 = readerui.document:getPageXPointer(3)

      local A = {
        page = xp2,
        pos0 = xp2,
        pos1 = xp2,
        text = "Highlight A",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      local B = {
        page = xp3,
        pos0 = xp3,
        pos1 = xp3,
        text = "Highlight B",
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
      }
      local C = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight C",
        datetime = "2026-01-01 09:00:00",
        drawer = "lighten",
      }

      readerui.annotation.annotations = { A, B }
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", { A, B })
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      util.writeToFile(json.encode({ A, B }), sync_instance.manager:getSyncCachePath(doc_file))

      local tmp_income = require("datastorage"):getTmpDir() .. "/" .. sync_instance.manager:_getAnnotationFilename(doc_file) .. ".income"
      util.writeToFile(json.encode({ C, A, B }), tmp_income)
      finally(function()
        os.remove(tmp_income)
        if readerui.highlight.edit_highlight_dialog then
          UIManager:closeIfShown(readerui.highlight.edit_highlight_dialog)
          readerui.highlight.edit_highlight_dialog = nil
        end
        sync_instance.manager.running = nil
      end)

      readerui.highlight:onShowHighlightDialog(2)
      assert.is_not_nil(readerui.highlight.edit_highlight_dialog)

      sync_instance.manager:addToChangedDocumentsFile(doc_file)
      sync_instance.manager:syncNow(doc_file)
      sync_instance.manager:dispatchNextSync()

      readerui.highlight.edit_highlight_dialog.buttons[1][1].callback()

      fastforward_ui_events()

      local texts = {}
      for _, ann in ipairs(readerui.annotation.annotations) do
        table.insert(texts, ann.text)
      end
      assert.are.same({ "Highlight C", "Highlight A" }, texts)
      assert.is_nil(sync_instance.manager.running)
    end)

    it("note editor open during sync preserves note after saving", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp2 = readerui.document:getPageXPointer(2)

      local B = {
        page = xp2,
        pos0 = xp2,
        pos1 = xp2,
        text = "Highlight B",
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
      }
      local C = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight C",
        datetime = "2026-01-01 09:00:00",
        drawer = "lighten",
      }

      readerui.annotation.annotations = { B }
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", { B })
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      util.writeToFile(json.encode({ B }), sync_instance.manager:getSyncCachePath(doc_file))

      local tmp_income = require("datastorage"):getTmpDir() .. "/" .. sync_instance.manager:_getAnnotationFilename(doc_file) .. ".income"
      util.writeToFile(json.encode({ C, B }), tmp_income)

      local input_dialog
      local old_show = UIManager.show
      UIManager.show = function(ui_mgr, widget, ...)
        if widget and widget.title == gettext("Edit note") then
          input_dialog = widget
        end
        return old_show(ui_mgr, widget, ...)
      end
      finally(function()
        os.remove(tmp_income)
        UIManager.show = old_show
        if input_dialog then
          UIManager:closeIfShown(input_dialog)
        end
        sync_instance.manager.running = nil
      end)

      readerui.bookmark:setBookmarkNote(1, false, nil, function() end)
      assert.is_not_nil(input_dialog)

      sync_instance.manager:addToChangedDocumentsFile(doc_file)
      sync_instance.manager:syncNow(doc_file)
      sync_instance.manager:dispatchNextSync()

      input_dialog:setInputText("my typed note")
      input_dialog.buttons[1][3].callback()

      fastforward_ui_events()

      local texts = {}
      for _, ann in ipairs(readerui.annotation.annotations) do
        table.insert(texts, ann.text)
      end
      assert.are.same({ "Highlight C", "Highlight B" }, texts)
      assert.are_equal("my typed note", readerui.annotation.annotations[2].note)
      assert.is_nil(sync_instance.manager.running)
    end)

    it("empty-book ConfirmBox appears after queued callback runs and Restore under dialog queues second apply", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local A = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight to restore",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      readerui.annotation.annotations = {}
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", {})
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      util.writeToFile(json.encode({ A }), sync_instance.manager:getSyncCachePath(doc_file))

      local tmp_income = require("datastorage"):getTmpDir() .. "/" .. sync_instance.manager:_getAnnotationFilename(doc_file) .. ".income"
      util.writeToFile(json.encode({ A }), tmp_income)

      local boxes = {}
      local old_show = UIManager.show
      UIManager.show = function(ui_mgr, widget, ...)
        if getmetatable(widget) == require("ui/widget/confirmbox") then
          table.insert(boxes, widget)
        end
        return old_show(ui_mgr, widget, ...)
      end
      finally(function()
        os.remove(tmp_income)
        UIManager.show = old_show
        for _, b in ipairs(boxes) do
          UIManager:close(b)
        end
        sync_instance.manager.running = nil
      end)

      local widget1 = require("ui/widget/widget"):new()
      readerui.annotation:trackChangingWidget(widget1)

      sync_instance.manager:addToChangedDocumentsFile(doc_file)
      sync_instance.manager:syncNow(doc_file)
      sync_instance.manager:dispatchNextSync()

      -- ConfirmBox appears only after the queued callback runs
      assert.are.equal(0, #boxes)

      widget1:onClose()
      fastforward_ui_events()

      assert.are.equal(1, #boxes)
      assert.are.equal(gettext("Move to trash"), boxes[1].ok_text)
      assert.are.equal(gettext("Restore"), boxes[1].cancel_text)

      -- Hold book with a second dialog before clicking Restore
      local widget2 = require("ui/widget/widget"):new()
      readerui.annotation:trackChangingWidget(widget2)

      boxes[1].cancel_callback()

      -- While widget2 is open, second apply and finish() are queued
      assert.are.equal(0, #readerui.annotation.annotations)
      assert.are.equal(doc_file, sync_instance.manager.running)

      widget2:onClose()
      fastforward_ui_events()

      -- Second apply and finish() run after dialog closes
      assert.are.equal(1, #readerui.annotation.annotations)
      assert.are.equal("Highlight to restore", readerui.annotation.annotations[1].text)
      assert.is_nil(sync_instance.manager.running)
      assert.is_not_nil(sync_instance.manager.last_sync_time[doc_file])
    end)
    it("restoreAnnotations waits for tracked dialog to close before restoring annotations and marking pending", function()
      local xp1 = readerui.document:getPageXPointer(1)
      local xp2 = readerui.document:getPageXPointer(2)

      local A = {
        page = xp1,
        pos0 = xp1,
        pos1 = xp1,
        text = "Highlight A",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      readerui.annotation.annotations = { A }
      readerui.annotation:updatePageNumbers(true)
      readerui.doc_settings:save("annotations", { A })
      readerui.doc_settings:flush()

      local doc_file = readerui.document.file
      sync_instance.manager:removeFromChangedDocumentsFileByPath(doc_file)
      assert.are.equal(0, (sync_instance.manager:getPendingChangedDocuments()))

      local widget = require("ui/widget/widget"):new()
      readerui.annotation:trackChangingWidget(widget)

      sync_instance:restoreAnnotations({
        {
          page = xp2,
          pos0 = xp2,
          pos1 = xp2,
          text = "Highlight to restore",
          datetime = "2026-01-01 09:00:00",
          deleted = true,
          drawer = "lighten",
        },
      }, true)

      -- With dialog open, book remains unchanged and book is not marked pending yet
      assert.are.equal(1, #readerui.annotation.annotations)
      assert.are.equal("Highlight A", readerui.annotation.annotations[1].text)
      assert.are.equal(0, (sync_instance.manager:getPendingChangedDocuments()))

      -- Dialog closes and one tick passes
      widget:onClose()
      fastforward_ui_events()

      -- Annotations restored and book marked pending
      assert.are.equal(2, #readerui.annotation.annotations)
      local texts = {}
      for _, ann in ipairs(readerui.annotation.annotations) do
        table.insert(texts, ann.text)
      end
      assert.are.same({ "Highlight A", "Highlight to restore" }, texts)
      local count_after, pending_docs = sync_instance.manager:getPendingChangedDocuments()
      assert.are.equal(1, count_after)
      assert.truthy(util.arrayContains(pending_docs, doc_file))
    end)

    it("applySyncedAnnotations never calls document:render() on open book", function()
      local old_render = readerui.document.render
      readerui.document.render = function()
        error("render should not be called")
      end
      finally(function()
        readerui.document.render = old_render
      end)

      sync_instance:applySyncedAnnotations(readerui.document, {})
    end)

    it("applySyncedAnnotations does not raise when open document has no render method", function()
      local old_doc = readerui.document
      local doc_no_render = setmetatable({
        file = old_doc.file,
        is_pdf = false,
      }, {
        __index = function(_, k)
          if k == "render" then return nil end
          return old_doc[k]
        end,
      })
      readerui.document = doc_no_render
      finally(function()
        readerui.document = old_doc
      end)

      sync_instance:applySyncedAnnotations(doc_no_render, {})
    end)

    it("applySyncedAnnotations repaints the open book, PDF included", function()
      local old_is_pdf = readerui.document.is_pdf
      readerui.document.is_pdf = true
      local dirty_target
      local old_setDirty = UIManager.setDirty
      UIManager.setDirty = function(self, widget, ...)
        dirty_target = widget
        return old_setDirty(self, widget, ...)
      end
      finally(function()
        readerui.document.is_pdf = old_is_pdf
        UIManager.setDirty = old_setDirty
      end)

      sync_instance:applySyncedAnnotations(readerui.document, {})
      assert.are_equal(readerui, dirty_target)
    end)

    it("applySyncedAnnotations resets thumbnail cache for removed highlights and broadcasts when empty", function()
      local xp4 = readerui.document:getPageXPointer(4)
      local xp9 = readerui.document:getPageXPointer(9)

      local A = {
        page = xp4,
        pos0 = xp4,
        pos1 = xp4,
        text = "Highlight A",
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
      }
      local B = {
        page = xp9,
        pos0 = xp9,
        pos1 = xp9,
        text = "Highlight B",
        datetime = "2026-01-01 10:05:00",
        drawer = "lighten",
      }

      local removed_caches = {}
      local old_removeFromCache = readerui.thumbnail.removeFromCache
      readerui.thumbnail.removeFromCache = function(self, hash_subs, ...)
        table.insert(removed_caches, hash_subs)
        return old_removeFromCache(self, hash_subs, ...)
      end
      finally(function()
        readerui.thumbnail.removeFromCache = old_removeFromCache
      end)

      -- Initial state: A (p4) and B (p9)
      sync_instance:applySyncedAnnotations(readerui.document, { A, B })
      removed_caches = {}

      -- Apply { A }: B is removed -> p9's cache must be evicted
      sync_instance:applySyncedAnnotations(readerui.document, { A })
      local p9_found = false
      for _, subs in ipairs(removed_caches) do
        for _, sub in ipairs(subs) do
          if sub == "p9-" then
            p9_found = true
            break
          end
        end
      end
      assert.is_true(p9_found)

      -- Apply {}: A is removed -> event must be broadcast and p4's cache evicted
      removed_caches = {}
      sync_instance:applySyncedAnnotations(readerui.document, {})
      local p4_found = false
      for _, subs in ipairs(removed_caches) do
        for _, sub in ipairs(subs) do
          if sub == "p4-" then
            p4_found = true
            break
          end
        end
      end
      assert.is_true(p4_found)
    end)

    it("applySyncedAnnotations on closed book marks annotations_externally_modified", function()
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

    it("format isolation: local [paging P1], base/income [rolling R1,R2] keeps R1 and R2 not deleted plus P1; active is [P1]", function()
      local P1 = {
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
        page = 3,
        pos0 = { x = 1, y = 2, page = 3 },
        pos1 = { x = 9, y = 2, page = 3 },
        text = "Paging P1",
      }
      local R1 = {
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
        page = "/body/p[1]/text().0",
        pos0 = "/body/p[1]/text().0",
        pos1 = "/body/p[1]/text().9",
        text = "Rolling R1",
      }
      local R2 = {
        datetime = "2026-01-01 10:30:00",
        drawer = "lighten",
        page = "/body/p[2]/text().0",
        pos0 = "/body/p[2]/text().0",
        pos1 = "/body/p[2]/text().9",
        text = "Rolling R2",
      }

      local merged, active = annotations_mod.merge({ P1 }, { R1, R2 }, { R1, R2 }, "number")
      assert.are_equal(1, #active)
      assert.are_equal(P1.text, active[1].text)
      assert.are_equal(3, #merged)
      for _, item in ipairs(merged) do
        assert.is_nil(item.deleted)
      end
    end)

    it("empty paging view of a rolling-annotated book: no restore prompt and no rolling items applied", function()
      local R1 = {
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
        page = "/body/p[1]/text().0",
        pos0 = "/body/p[1]/text().0",
        pos1 = "/body/p[1]/text().9",
        text = "Rolling R1",
      }
      local R2 = {
        datetime = "2026-01-01 10:30:00",
        drawer = "lighten",
        page = "/body/p[2]/text().0",
        pos0 = "/body/p[2]/text().0",
        pos1 = "/body/p[2]/text().9",
        text = "Rolling R2",
      }

      readerui.annotation.annotations = {}
      readerui.rolling = false
      readerui.paging = true
      finally(function()
        readerui.rolling = true
        readerui.paging = false
      end)

      assert.is_nil(sync_instance.manager:_applyBackgroundSync(
        readerui.document.file,
        json.encode({ R1, R2 }),
        json.encode({ R1, R2 }),
        true
      ))
      assert.are_equal(0, #readerui.annotation.annotations)
    end)

    it("format isolation: back in CRE with base/income containing P1: P1 is kept, not tombstoned, and not in active", function()
      local P1 = {
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
        page = 3,
        pos0 = { x = 1, y = 2, page = 3 },
        pos1 = { x = 9, y = 2, page = 3 },
        text = "Paging P1",
      }
      local R1 = {
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
        page = "/body/p[1]/text().0",
        pos0 = "/body/p[1]/text().0",
        pos1 = "/body/p[1]/text().9",
        text = "Rolling R1",
      }

      local merged, active = annotations_mod.merge({ R1 }, { R1, P1 }, { R1, P1 }, "string")
      assert.are_equal(1, #active)
      assert.are_equal(R1.text, active[1].text)
      assert.are_equal(2, #merged)
      for _, item in ipairs(merged) do
        assert.is_nil(item.deleted)
      end
    end)
  end)

  describe("Closed-book sidecar synchronization", function()
    it("handles document engine format swap across getAnnotationsForDocument and applySyncedAnnotations", function()
      local closed_file = test_data_dir .. "/closed_s1.epub"
      local DocSettings = require("docsettings")
      os.execute("rm -rf " .. closed_file .. " " .. closed_file .. ".sdr; touch " .. closed_file)
      local ds = DocSettings:open(closed_file)
      local P = {
        datetime = "2026-01-01 11:00:00",
        drawer = "lighten",
        page = 3,
        pos0 = { x = 1, y = 2, page = 3 },
        pos1 = { x = 9, y = 2, page = 3 },
        text = "Paging highlight",
      }
      local E = {
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
        page = "/body/p[1]/text().0",
        pos0 = "/body/p[1]/text().0",
        pos1 = "/body/p[1]/text().9",
        text = "Rolling highlight",
      }
      ds:save("annotations", { P })
      ds:save("annotations_rolling", { E })
      ds:flush()
      finally(function()
        os.remove(closed_file)
        os.execute("rm -rf " .. closed_file .. ".sdr")
      end)

      -- 1. getAnnotationsForDocument loads via loadFromSettings (swaps P into paging, returns E)
      local list = sync_instance.manager:getAnnotationsForDocument(closed_file)
      assert.are_equal(1, #list)
      assert.are_equal("Rolling highlight", list[1].text)

      -- 2. applySyncedAnnotations preserves swapped paging list and clears stale rolling
      sync_instance:applySyncedAnnotations({ file = closed_file }, list)

      local reloaded_ds = DocSettings:open(closed_file)
      local anns = reloaded_ds:readTable("annotations")
      assert.are_equal(1, #anns)
      assert.are_equal("Rolling highlight", anns[1].text)
      local paging = reloaded_ds:readTable("annotations_paging")
      assert.are_equal(1, #paging)
      assert.are_equal("Paging highlight", paging[1].text)
      assert.is_nil(reloaded_ds:readTable("annotations_rolling"))
      assert.is_true(reloaded_ds:isTrue("annotations_externally_modified"))
    end)

    it("quarantines invalid closed-book annotations across getAnnotationsForDocument and applySyncedAnnotations", function()
      local closed_file = test_data_dir .. "/closed_s2.epub"
      local DocSettings = require("docsettings")
      os.execute("rm -rf " .. closed_file .. " " .. closed_file .. ".sdr; touch " .. closed_file)
      local ds = DocSettings:open(closed_file)
      local E = {
        datetime = "2026-01-01 10:00:00",
        drawer = "lighten",
        page = "/body/p[1]/text().0",
        pos0 = "/body/p[1]/text().0",
        pos1 = "/body/p[1]/text().9",
        text = "Valid highlight",
      }
      local Ebad = {
        datetime = "2026-01-01 12:00:00",
        page = "/body/p[2]/text().0",
        pos0 = "/body/p[2]/text().0",
        pos1 = "/body/p[2]/text().9",
        text = "Invalid highlight without drawer",
      }
      ds:save("annotations", { E, Ebad })
      ds:flush()
      finally(function()
        os.remove(closed_file)
        os.execute("rm -rf " .. closed_file .. ".sdr")
      end)

      -- 1. getAnnotationsForDocument filters out invalid items via loadFromSettings
      local list = sync_instance.manager:getAnnotationsForDocument(closed_file)
      assert.are_equal(1, #list)
      assert.are_equal("Valid highlight", list[1].text)

      -- 2. applySyncedAnnotations preserves quarantined invalid list
      sync_instance:applySyncedAnnotations({ file = closed_file }, list)

      local reloaded_ds = DocSettings:open(closed_file)
      local anns = reloaded_ds:readTable("annotations")
      assert.are_equal(1, #anns)
      assert.are_equal("Valid highlight", anns[1].text)
      local invalid = reloaded_ds:readTable("annotations_invalid")
      assert.are_equal(1, #invalid)
      assert.are_equal("Invalid highlight without drawer", invalid[1].text)
      assert.is_true(reloaded_ds:isTrue("annotations_externally_modified"))
    end)
  end)
end)
