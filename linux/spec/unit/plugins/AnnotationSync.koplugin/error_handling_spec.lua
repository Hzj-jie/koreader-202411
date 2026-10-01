describe("AnnotationSync Integration - Battery 4 (Error Handling)", function()
  local ReaderUI, UIManager, Geom, SyncService
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_error_tmp"
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
    sync_instance.settings.network_auto_sync = false
    sync_instance.settings.use_filename = false
    sync_instance.settings.last_sync = "Never"

    os.remove(sync_instance.manager:changedDocumentsFile())
    test_utils.mock_sync_service(SyncService)
  end)

  describe("4.1 Network & Server Errors", function()
    it("should keep document dirty if server is offline", function()
      sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)
      assert.is_true(sync_instance.manager:hasPendingChangedDocuments())

      -- Mock SyncService.sync to simulate a failure (callback never called)
      SyncService.sync = function(server, local_path, sync_cb, is_silent, finish_cb)
        -- Failure: callback is not called
        if finish_cb then
          finish_cb(false)
        end
        return
      end

      sync_instance:manualSync()

      -- Fixed: It should now remain dirty because the callback (which triggers removal) was never called
      assert.is_true(sync_instance.manager:hasPendingChangedDocuments())
      assert.is_equal("Never", sync_instance.settings.last_sync)
    end)

    it(
      "should handle malformed remote data gracefully and abort upload",
      function()
        local income_file = test_utils.write_mock_json(
          test_data_dir,
          "malformed.json",
          "{ malformed json ..."
        )

        local upload_called = false
        SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
          local success = callback(local_path, local_path, income_file)
          if success then
            upload_called = true
          end
          if finish_cb then
            finish_cb(success)
          end
          return success
        end

        sync_instance:manualSync()
        assert.is_false(
          upload_called,
          "Sync should have aborted and not proceeded to upload"
        )
        assert.is_equal("Never", sync_instance.settings.last_sync)
      end
    )

    it("updates last_sync timestamp when manualSync succeeds", function()
      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local cached_dest = local_path .. ".sync"
        local success = callback(local_path, cached_dest, local_path)
        if success then
          require("ffi/util").copyFile(local_path, cached_dest)
        end
        if finish_cb then
          finish_cb(true)
        end
        return true
      end

      sync_instance:manualSync()

      assert.truthy(sync_instance.settings.last_sync:find("%(Manual Sync%)"))
    end)
  end)

  describe("4.2 File System Errors", function()
    it("should handle read-only sidecar directory gracefully", function()
      local DataStorage = require("datastorage")
      local old_getTmpDir = DataStorage.getTmpDir
      DataStorage.getTmpDir = function()
        return "/read-only-dir"
      end

      local ok = sync_instance.manager:syncDocument(readerui.document, true)
      assert.is_false(
        ok,
        "syncDocument should fail gracefully on read-only sidecar directory"
      )

      DataStorage.getTmpDir = old_getTmpDir
    end)
  end)

  describe("4.3 Concurrency", function()
    it("should handle concurrent sync requests safely", function()
      local call_count = 0
      local old_sync = SyncService.sync
      SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
        call_count = call_count + 1
        local result = callback(local_path, local_path, local_path)
        local ffiutil = require("ffi/util")
        local cached_dest = local_path .. ".sync"
        ffiutil.copyFile(local_path, cached_dest)
        if finish_cb then
          finish_cb(result)
        end
        return result
      end

      sync_instance:manualSync()
      sync_instance:manualSync()

      assert.are.equal(
        2,
        call_count,
        "Both manualSync calls should execute safely"
      )
      SyncService.sync = old_sync
    end)
  end)

  describe("4.4 Robustness", function()
    it("should handle special characters in highlights (Emojis)", function()
      local emoji_text = "Emoji highlight 🌟"
      local ann = {
        drawer = "lighten",
        page = "pos0",
        pos0 = "pos0",
        pos1 = "pos1",
        text = emoji_text,
        datetime = "2026-01-01 12:00:00",
      }
      table.insert(readerui.annotation.annotations, ann)

      local ok = sync_instance.manager:syncDocument(readerui.document, true)
      assert.is_true(
        ok,
        "syncDocument should succeed with emojis in highlight text"
      )
      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_equal(emoji_text, readerui.annotation.annotations[1].text)

      -- Verify on-disk serialization and persistence preserves emoji
      local sync_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local on_disk_data =
        require("plugins/AnnotationSync.koplugin/utils").read_json(sync_path)
      assert.is_table(on_disk_data)
      local found_emoji = false
      for _, item in pairs(on_disk_data) do
        if item.text == emoji_text then
          found_emoji = true
          break
        end
      end
      assert.is_true(
        found_emoji,
        "On-disk sync cache should contain properly preserved emoji text"
      )
    end)
  end)
end)
