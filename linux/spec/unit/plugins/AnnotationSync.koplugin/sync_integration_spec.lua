describe("AnnotationSync Core Integration", function()
  local ReaderUI, UIManager, SyncService, Geom
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util, annotations_mod
  local readerui, sync_instance
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
    return ann, annotations_mod.annotation_key(ann)
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

      local ann2, key2 = create_ann_from_db(2)
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_disjoint.json",
        { [key2] = ann2 }
      )

      SyncService.sync = function(server, local_path, callback, upload_only)
        local cached_dest = local_path .. ".sync"
        callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)

      assert.is_equal(2, #readerui.annotation.annotations)
    end)

    it("resolves conflicts using timestamps (latest wins)", function()
      local ann_l, key =
        create_ann_from_db(1, "Local Newer", "2026-02-02 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r, _ =
        create_ann_from_db(1, "Remote Older", "2026-02-01 12:00:00")
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_conflict.json",
        { [key] = ann_r }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ [key] = ann_r }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only)
        local cached_dest = local_path .. ".sync"
        callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)
      assert.is_equal("Local Newer", readerui.annotation.annotations[1].note)
    end)

    it("resurrects zombie if modification is newer than deletion", function()
      -- Remote has deletion, but local has a NEWER modification
      local ann_l, key = create_ann_from_db(1, "Revived", "2026-02-05 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r, _ = create_ann_from_db(1)
      ann_r.deleted = true
      ann_r.datetime_updated = "2026-02-01 12:00:00"

      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_zombie.json",
        { [key] = ann_r }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ [key] = ann_r }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only)
        local cached_dest = local_path .. ".sync"
        callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
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
      local ann, key = create_ann_from_db(1)
      table.insert(readerui.annotation.annotations, ann)

      local ann_del = util.tableDeepCopy(ann)
      ann_del.deleted = true
      ann_del.datetime_updated = "2026-02-02 12:00:00"

      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_del.json",
        { [key] = ann_del }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ [key] = ann }))
      fc:close()

      SyncService.sync = function(server, local_path, callback, upload_only)
        local cached_dest = local_path .. ".sync"
        callback(local_path, cached_dest, income_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
        return true
      end

      sync_instance:manualSync()
      os.remove(income_path)
      assert.is_equal(0, #readerui.annotation.annotations)
    end)

    it(
      "should return false from sync_callback when remote file is missing and local file is empty",
      function()
        local local_path =
          test_utils.write_mock_json(test_data_dir, "empty_local.json", {})
        local last_sync_path =
          test_utils.write_mock_json(test_data_dir, "empty_last.json", {})
        local res = annotations_mod.sync_callback(
          readerui.document,
          local_path,
          last_sync_path,
          nil,
          false
        )
        assert.is_false(res)
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
        SyncService.sync = function(server, local_path, callback, is_silent)
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
      SyncService.sync = function(server, local_path, callback, is_silent)
        local cached_dest = local_path .. ".sync"
        callback(local_path, cached_dest, local_path)
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
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
end)
