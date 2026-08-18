describe("AnnotationSync Automation & Settings", function()
  local ReaderUI, UIManager, SyncService, Geom
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_sync_automation_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/spec/unit/test_utils")
    disable_plugins()
    Geom = require("ui/geometry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    json = require("json")
    util = require("util")

    highlight_db =
      require("plugins/AnnotationSync.koplugin/spec/unit/highlight_db")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server" })
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
    os.remove(sync_instance.manager:changedDocumentsFile())
    test_utils.mock_sync_service(SyncService)
  end)

  describe("Settings", function()
    it("respects naming convention settings", function()
      test_utils.emulate_highlight(readerui, highlight_db[1])

      local captured_path
      SyncService.sync = function(server, local_path, callback, upload_only)
        captured_path = local_path
        return callback(local_path, local_path, local_path)
      end

      sync_instance.settings.use_filename = false
      sync_instance:manualSync()
      assert.truthy(
        captured_path:match(
          util.partialMD5(readerui.document.file) .. "%.json$"
        )
      )

      sync_instance.settings.use_filename = true
      sync_instance:manualSync()
      assert.truthy(captured_path:match("juliet%.epub%.json$"))
    end)
  end)

  describe("Automation", function()
    it(
      "triggers background incremental sync on onTimesChange_1M when network_auto_sync is enabled",
      function()
        sync_instance.settings.network_auto_sync = true
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local sync_triggered = false
        SyncService.sync = function(server, local_path, callback, upload_only)
          sync_triggered = true
          callback(local_path, local_path, local_path)
        end

        local old_scheduleIn = UIManager.scheduleIn
        UIManager.scheduleIn = function(self_ui, seconds, callback)
          callback()
        end

        sync_instance:onTimesChange_1M()

        assert.is_true(sync_triggered)
        UIManager.scheduleIn = old_scheduleIn
      end
    )

    it("batch processes multiple documents correctly", function()
      local doc1 = readerui.document.file
      local doc2 = "spec/front/unit/data/leaves.epub"

      sync_instance.manager:addToChangedDocumentsFile(doc1)
      sync_instance.manager:addToChangedDocumentsFile(doc2)

      local synced_files = {}
      SyncService.sync = function(server, local_path, callback, upload_only)
        table.insert(synced_files, local_path)
        callback(local_path, local_path, local_path)
      end

      sync_instance.manager:syncAllChangedDocuments()
      fastforward_ui_events()
      assert.is_equal(2, #synced_files)
    end)

    it(
      "skips onTimesChange_1M when background sync is already running",
      function()
        sync_instance.settings.network_auto_sync = true
        sync_instance.manager.is_syncing_pending_bg = true

        local bg_called = false
        local old_bgFunc = sync_instance.manager.syncPendingDocumentsBg
        sync_instance.manager.syncPendingDocumentsBg = function()
          bg_called = true
        end

        sync_instance:onTimesChange_1M()

        assert.is_false(bg_called)
        sync_instance.manager.syncPendingDocumentsBg = old_bgFunc
        sync_instance.manager.is_syncing_pending_bg = false
      end
    )

    it("aborts active background sync when Sync All is triggered", function()
      sync_instance.manager.is_syncing_pending_bg = true
      sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

      sync_instance.manager:syncAllChangedDocuments()
      fastforward_ui_events()

      assert.is_false(sync_instance.manager.is_syncing_pending_bg)
    end)

    it(
      "uses 5 second pacing intervals in background sync scheduleIn",
      function()
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local scheduled_seconds = nil
        local old_scheduleIn = UIManager.scheduleIn
        UIManager.scheduleIn = function(self_ui, seconds, callback)
          scheduled_seconds = seconds
          callback()
        end

        sync_instance.manager:syncPendingDocumentsBg()

        assert.is_equal(5, scheduled_seconds)
        UIManager.scheduleIn = old_scheduleIn
      end
    )

    it(
      "halts background sync if network_auto_sync is disabled during execution",
      function()
        sync_instance.settings.network_auto_sync = true
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local old_scheduleIn = UIManager.scheduleIn
        local scheduled_cb = nil
        UIManager.scheduleIn = function(self_ui, seconds, callback)
          scheduled_cb = callback
        end

        sync_instance.manager:syncPendingDocumentsBg()
        assert.is_true(sync_instance.manager.is_syncing_pending_bg)

        -- User turns off network_auto_sync while sync is pending
        sync_instance.settings.network_auto_sync = false
        if scheduled_cb then
          scheduled_cb()
        end

        assert.is_false(sync_instance.manager.is_syncing_pending_bg)
        UIManager.scheduleIn = old_scheduleIn
      end
    )
  end)
end)
