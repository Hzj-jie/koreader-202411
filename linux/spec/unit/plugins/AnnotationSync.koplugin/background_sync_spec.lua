describe("Background Sync Behavior", function()
  local ReaderUI, UIManager, Trapper, SyncService, Geom
  local AnnotationSyncPlugin, SyncManager, remote, json, test_utils, util
  local readerui, plugin_instance, sync_manager
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_bg_sync_tmp"
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
    Trapper = require("ui/trapper")
    SyncService = require("apps/cloudstorage/syncservice")
    json = require("json")
    util = require("util")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
    SyncManager = require("plugins/AnnotationSync.koplugin/manager")
    remote = require("plugins/AnnotationSync.koplugin/remote")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server", type = "webdav" })
    )

    readerui, plugin_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    sync_manager = plugin_instance.manager
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    require("ui/widget/imageviewer").new = _G.old_ImageViewer_new
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
    package.loaded["plugins/AnnotationSync.koplugin/manager"] = nil
    package.loaded["plugins/AnnotationSync.koplugin/remote"] = nil
  end)

  before_each(function()
    UIManager:show(readerui)
    fastforward_ui_events()
    readerui.annotation.annotations = {}
    os.remove(sync_manager:changedDocumentsFile())
    test_utils.mock_sync_service(SyncService)
    sync_manager.is_syncing_pending_bg = false
    plugin_instance.settings.network_auto_sync = true
  end)

  describe("Main thread preparation and validation", function()
    it("skips background sync when network is offline", function()
      local NetworkMgr = require("ui/network/manager")
      local old_isConn = NetworkMgr.isConnected
      NetworkMgr.isConnected = function()
        return false
      end

      sync_manager:addToChangedDocumentsFile(readerui.document.file)
      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      sync_manager:syncPendingDocumentsBg()

      assert.is_equal(initial_count, #jobs)
      assert.is_false(sync_manager.is_syncing_pending_bg)
      NetworkMgr.isConnected = old_isConn
    end)

    it("skips background sync when changed_documents is empty", function()
      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      sync_manager:syncPendingDocumentsBg()

      assert.is_equal(initial_count, #jobs)
      assert.is_false(sync_manager.is_syncing_pending_bg)
    end)

    it("prunes missing files on disk immediately in main thread", function()
      local missing_file = "/nonexistent/path/missing_book.epub"
      sync_manager:addToChangedDocumentsFile(missing_file)
      sync_manager:addToChangedDocumentsFile(readerui.document.file)

      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      sync_manager:syncPendingDocumentsBg()

      -- Missing file is pruned immediately
      local _, changed = sync_manager:getPendingChangedDocuments()
      assert.is_nil(changed[missing_file])
      assert.is_true(changed[readerui.document.file])

      -- Only the existing file was queued
      assert.is_equal(initial_count + 1, #jobs)
    end)

    it(
      "does not insert background job when all pending files are missing",
      function()
        local missing_file = "/nonexistent/path/missing_book.epub"
        sync_manager:addToChangedDocumentsFile(missing_file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:syncPendingDocumentsBg()

        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
        assert.is_equal(initial_count, #jobs)
        assert.is_false(sync_manager.is_syncing_pending_bg)
      end
    )

    it(
      "flushes settings and serializes JSON in main thread before job dispatch",
      function()
        local flush_called = false
        local old_flush = sync_manager.flushSettings
        sync_manager.flushSettings = function(self)
          flush_called = true
          old_flush(self)
        end

        sync_manager:addToChangedDocumentsFile(readerui.document.file)
        sync_manager:syncPendingDocumentsBg()

        assert.is_true(flush_called)
        sync_manager.flushSettings = old_flush
      end
    )
  end)

  describe("BackgroundJobs fork dispatching and execution", function()
    it(
      "registers a best-effort fork job in pluginshare.backgroundJobs",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:syncPendingDocumentsBg()

        assert.is_equal(initial_count + 1, #jobs)
        local job = jobs[#jobs]
        assert.is_equal("best-effort", job.when)
        assert.is_equal("fork", job.executable)
        assert.is_function(job.action)
        assert.is_function(job.callback)
        assert.is_true(sync_manager.is_syncing_pending_bg)
      end
    )

    it(
      "executes remote sync inside action without showing UI modals in silent mode",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        local sync_called_silent = nil
        SyncService.sync = function(server, local_path, callback, is_silent)
          sync_called_silent = is_silent
          return callback(local_path, local_path, local_path)
        end

        local old_show = UIManager.show
        local show_called = false
        UIManager.show = function(self_ui, widget)
          show_called = true
        end

        sync_manager:syncPendingDocumentsBg()
        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]

        local action_res = job.action()

        assert.is_true(sync_called_silent)
        assert.is_false(show_called)
        assert.is_table(action_res)
        assert.is_equal(1, #action_res)
        assert.is_equal(readerui.document.file, action_res[1].file)
        assert.is_true(action_res[1].success)

        UIManager.show = old_show
      end
    )

    it(
      "handles remote sync failure or crash inside action gracefully",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        SyncService.sync = function(server, local_path, callback, is_silent)
          error("Simulated network crash during background sync")
        end

        sync_manager:syncPendingDocumentsBg()
        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]

        local action_res = job.action()
        assert.is_table(action_res)
        assert.is_equal(0, #action_res)
      end
    )
  end)

  describe("Main thread callback processing", function()
    it(
      "removes successfully synced documents from changed_documents and updates sync timestamp",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)
        sync_manager:syncPendingDocumentsBg()

        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]

        job.callback({
          result = {
            { file = readerui.document.file, success = true, merged_list = {} },
          },
        })

        assert.is_false(sync_manager.is_syncing_pending_bg)
        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
        assert.truthy(
          plugin_instance.settings.last_sync:match("Auto Sync %(1%)")
        )
      end
    )

    it("applies synced annotations to active ReaderUI document", function()
      sync_manager:addToChangedDocumentsFile(readerui.document.file)
      sync_manager:syncPendingDocumentsBg()

      local job =
        require("pluginshare").backgroundJobs[#require("pluginshare").backgroundJobs]
      local dummy_ann = { { text = "Background Synced Annotation", page = 1 } }

      job.callback({
        result = {
          {
            file = readerui.document.file,
            success = true,
            merged_list = dummy_ann,
          },
        },
      })

      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_equal(
        "Background Synced Annotation",
        readerui.annotation.annotations[1].text
      )
    end)

    it(
      "does not alter active ReaderUI annotations for unrelated inactive synced documents",
      function()
        local inactive_doc = "spec/front/unit/data/leaves.epub"
        sync_manager:addToChangedDocumentsFile(inactive_doc)
        sync_manager:syncPendingDocumentsBg()

        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]
        local dummy_ann = { { text = "Annotation for Leaves", page = 1 } }

        job.callback({
          result = {
            { file = inactive_doc, success = true, merged_list = dummy_ann },
          },
        })

        assert.is_equal(0, #readerui.annotation.annotations)
        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
      end
    )

    it(
      "safely resets is_syncing_pending_bg on nil or malformed job result",
      function()
        sync_manager.is_syncing_pending_bg = true
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        sync_manager:syncPendingDocumentsBg()
        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]

        job.callback({ result = nil })
        assert.is_false(sync_manager.is_syncing_pending_bg)

        sync_manager.is_syncing_pending_bg = true
        job.callback({ result = "invalid_string" })
        assert.is_false(sync_manager.is_syncing_pending_bg)
      end
    )
  end)

  describe("Silent remote sync warnings", function()
    it(
      "suppresses InfoMessage when cloud provider is unavailable in silent mode",
      function()
        local old_show = UIManager.show
        local show_called = false
        UIManager.show = function(self_ui, widget)
          show_called = true
        end

        local mock_w = {
          ui = {},
          settings = { sync_server = { url = "http://mock" } },
        }

        package.loaded["apps/cloudstorage/syncservice"] = nil
        remote.sync_annotations(mock_w, {}, "test.json", function() end, false)

        assert.is_false(show_called)
        UIManager.show = old_show
        package.loaded["apps/cloudstorage/syncservice"] = SyncService
      end
    )

    it(
      "suppresses InfoMessage when cloud destination server is missing in silent mode",
      function()
        local old_show = UIManager.show
        local show_called = false
        UIManager.show = function(self_ui, widget)
          show_called = true
        end

        local mock_w = {
          ui = {
            cloudstorage = {
              sync = function() end,
            },
          },
          settings = {},
        }

        remote.sync_annotations(mock_w, {}, "test.json", function() end, false)

        assert.is_false(show_called)
        UIManager.show = old_show
      end
    )
  end)
end)
