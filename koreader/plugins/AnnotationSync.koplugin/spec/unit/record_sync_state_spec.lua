describe("AnnotationSync recordSyncState & Network online guards", function()
  local ReaderUI, UIManager, SyncService
  local AnnotationSyncPlugin, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = os.getenv("PWD") .. "/test_sync_record_state_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/spec/unit/test_utils")
    disable_plugins()
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    json = require("json")
    util = require("util")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

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
    test_utils.mock_sync_service(SyncService)
  end)

  describe("recordSyncState unit tests", function()
    it("correctly formats and records last_sync timestamp with descriptor", function()
      sync_instance.manager:recordSyncState("Manual Sync")
      assert.truthy(sync_instance.settings.last_sync:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %((Manual Sync)%)"))

      sync_instance.manager:recordSyncState("Sync All")
      assert.truthy(sync_instance.settings.last_sync:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %((Sync All)%)"))

      sync_instance.manager:recordSyncState("Auto Sync (5)")
      assert.truthy(sync_instance.settings.last_sync:match("%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d %((Auto Sync %(5%))%)"))
    end)

    it("handles nil or empty descriptor gracefully", function()
      sync_instance.manager:recordSyncState(nil)
      assert.truthy(sync_instance.settings.last_sync:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"))

      sync_instance.manager:recordSyncState("")
      assert.truthy(sync_instance.settings.last_sync:match("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d$"))
    end)
  end)

  describe("NetworkMgr runWhenOnline guard in syncAllChangedDocuments", function()
    it("executes sync when network is online", function()
      local NetworkMgr = require("ui/network/manager")
      local old_runWhenOnline = NetworkMgr.runWhenOnline
      local run_online_called = false

      NetworkMgr.runWhenOnline = function(self, callback)
        run_online_called = true
        callback()
        return true
      end

      sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)
      sync_instance.manager:syncAllChangedDocuments()

      assert.is_true(run_online_called)
      assert.truthy(sync_instance.settings.last_sync:match("Sync All"))

      NetworkMgr.runWhenOnline = old_runWhenOnline
    end)

    it("aborts execution when network is offline and runWhenOnline returns false", function()
      local NetworkMgr = require("ui/network/manager")
      local old_runWhenOnline = NetworkMgr.runWhenOnline
      local run_online_called = false
      local old_last_sync = sync_instance.settings.last_sync

      NetworkMgr.runWhenOnline = function(self, callback)
        run_online_called = true
        return false
      end

      sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)
      sync_instance.manager:syncAllChangedDocuments()

      assert.is_true(run_online_called)
      assert.are.equal(old_last_sync, sync_instance.settings.last_sync)

      NetworkMgr.runWhenOnline = old_runWhenOnline
    end)
  end)
end)
