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

    local Device = require("device")
    local old_hasWifiToggle = Device.hasWifiToggle
    Device.hasWifiToggle = function()
      return true
    end
    package.loaded["ui/network/networklistener"] = nil
    local NetworkListener = require("ui/network/networklistener")
    Device.hasWifiToggle = old_hasWifiToggle

    readerui, plugin_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    readerui:registerModule(
      "networklistener",
      NetworkListener:new({
        document = readerui.document,
        view = readerui.view,
        ui = readerui,
      })
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
    os.remove(sync_manager:changedDocumentsFile())
    UIManager:show(readerui)
    fastforward_ui_events()
    readerui.annotation.annotations = {}
    test_utils.mock_sync_service(SyncService)
    require("background_jobs").clearKeys()
    local jobs = require("pluginshare").backgroundJobs
    for k in pairs(jobs) do
      jobs[k] = nil
    end
    plugin_instance.settings.network_auto_sync = true
  end)

  after_each(function()
    os.remove(sync_manager:changedDocumentsFile())
    local jobs = require("pluginshare").backgroundJobs
    for k in pairs(jobs) do
      jobs[k] = nil
    end
    require("background_jobs").clearKeys()
  end)

  describe("Main thread preparation and validation", function()
    it(
      "defers background sync via NetworkListener without notification when network is offline (Issue #492)",
      function()
        local NetworkMgr = require("ui/network/manager")
        local NetworkListener = require("ui/network/networklistener")
        local Notification = require("ui/widget/notification")
        local old_isConn = NetworkMgr.isConnected
        local old_isOnline = NetworkMgr.isOnline
        local old_runOnline = NetworkMgr.runWhenOnline
        local old_notify = Notification.notify

        local notify_called = false
        Notification.notify = function()
          notify_called = true
        end

        local run_online_called = false
        NetworkMgr.runWhenOnline = function()
          run_online_called = true
        end

        NetworkMgr.isConnected = function()
          return false
        end
        NetworkMgr.isOnline = function()
          return false
        end

        local ok, err = pcall(function()
          sync_manager:addToChangedDocumentsFile(readerui.document.file)
          local jobs = require("pluginshare").backgroundJobs
          local initial_count = #jobs

          sync_manager:syncPendingDocumentsBg()

          -- Whisper sync must NOT call runWhenOnline or trigger notification popup
          assert.is_false(run_online_called)
          assert.is_false(notify_called)

          -- No background runner job queued directly while offline
          assert.is_equal(initial_count, #jobs)
          -- But queued silently in NetworkListener for when online
          assert.is_equal("0 / 1", NetworkListener:countsOfPendingJobs())

          NetworkListener:onNetworkOnline()
          fastforward_ui_events()
        end)

        NetworkMgr.isConnected = old_isConn
        NetworkMgr.isOnline = old_isOnline
        NetworkMgr.runWhenOnline = old_runOnline
        Notification.notify = old_notify

        if not ok then
          error(err)
        end
      end
    )

    it("skips background sync when changed_documents is empty", function()
      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      sync_manager:syncPendingDocumentsBg()

      assert.is_equal(initial_count, #jobs)
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
      "registers an asap fork job in pluginshare.backgroundJobs via insertKeyed",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:syncPendingDocumentsBg()

        assert.is_equal(initial_count + 1, #jobs)
        local job = jobs[#jobs]
        assert.is_equal("asap", job.when)
        assert.is_equal("fork", job.executable)
        assert.is_function(job.action)
        assert.is_function(job.callback)
      end
    )

    it(
      "deduplicates concurrent sync requests while a background job is in-flight",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:syncPendingDocumentsBg()
        sync_manager:syncPendingDocumentsBg()

        -- Only 1 job is inserted thanks to insertKeyed
        assert.is_equal(initial_count + 1, #jobs)
      end
    )

    it("queues distinct fork jobs for multiple changed documents", function()
      local doc1 = readerui.document.file
      local doc2 = test_data_dir .. "/doc2.epub"
      require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
      sync_manager:addToChangedDocumentsFile(doc1)
      sync_manager:addToChangedDocumentsFile(doc2)

      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      sync_manager:syncPendingDocumentsBg()

      -- Queues 2 separate background jobs
      assert.is_equal(initial_count + 2, #jobs)
      os.remove(doc2)
    end)

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
        assert.is_equal(readerui.document.file, action_res.file)
        assert.is_true(action_res.success)

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
        assert.is_equal(readerui.document.file, action_res.file)
        assert.is_false(action_res.success)
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
            file = readerui.document.file,
            success = true,
            merged_list = {},
          },
        })

        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
        assert.truthy(plugin_instance.settings.last_sync:match("Auto Sync"))
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
          file = readerui.document.file,
          success = true,
          merged_list = dummy_ann,
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
        local inactive_doc = test_data_dir .. "/doc2.epub"
        require("ffi/util").copyFile(
          "spec/front/unit/data/juliet.epub",
          inactive_doc
        )
        sync_manager:addToChangedDocumentsFile(inactive_doc)
        sync_manager:syncPendingDocumentsBg()

        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]
        local dummy_ann = { { text = "Annotation for Leaves", page = 1 } }

        job.callback({
          result = {
            file = inactive_doc,
            success = true,
            merged_list = dummy_ann,
          },
        })

        assert.is_equal(0, #readerui.annotation.annotations)
        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
      end
    )

    it("safely handles nil or malformed job result in callback", function()
      sync_manager:addToChangedDocumentsFile(readerui.document.file)

      sync_manager:syncPendingDocumentsBg()
      local job =
        require("pluginshare").backgroundJobs[#require("pluginshare").backgroundJobs]

      -- Malformed results should not throw errors
      job.callback({ result = nil })
      job.callback({ result = "invalid_string" })

      -- The changed document remains pending
      local total, _ = sync_manager:getPendingChangedDocuments()
      assert.is_equal(1, total)
    end)
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

        local old_preload = package.preload["apps/cloudstorage/syncservice"]
        package.preload["apps/cloudstorage/syncservice"] = function()
          error("SyncService disabled for test")
        end
        local old_loaded_ss = package.loaded["apps/cloudstorage/syncservice"]
        package.loaded["apps/cloudstorage/syncservice"] = nil

        package.loaded["plugins/AnnotationSync.koplugin/remote"] = nil
        local test_remote = require("plugins/AnnotationSync.koplugin/remote")

        local dummy_json = test_data_dir .. "/test_silent_provider.json"
        test_remote.sync_annotations(
          mock_w,
          {},
          dummy_json,
          function() end,
          false
        )

        assert.is_false(show_called)
        UIManager.show = old_show

        package.preload["apps/cloudstorage/syncservice"] = old_preload
        package.loaded["apps/cloudstorage/syncservice"] = old_loaded_ss
        package.loaded["plugins/AnnotationSync.koplugin/remote"] = nil
        remote = require("plugins/AnnotationSync.koplugin/remote")
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

        local dummy_json = test_data_dir .. "/test_silent_dest.json"
        remote.sync_annotations(mock_w, {}, dummy_json, function() end, false)

        assert.is_false(show_called)
        UIManager.show = old_show
      end
    )
  end)

  describe("Remote sync completion and perform_sync lifecycle", function()
    it(
      "calls on_complete strictly after sync finishes, passing captured merged_list",
      function()
        local order = {}
        local old_sync = SyncService.sync
        SyncService.sync = function(server, local_path, callback, silent)
          table.insert(order, "sync_start")
          local cb_res = callback(local_path, local_path, local_path, 200)
          table.insert(order, "upload")
          return true
        end

        local annotations =
          require("plugins/AnnotationSync.koplugin/annotations")
        local old_sync_cb = annotations.sync_callback
        local dummy_merged = { { page = 1, text = "test" } }
        annotations.sync_callback = function()
          table.insert(order, "sync_cb")
          return true, dummy_merged
        end

        local mock_w = {
          ui = {},
          settings = { sync_server = { url = "http://mock", type = "dropbox" } },
          manager = {
            getSyncCachePath = function()
              return nil
            end,
          },
        }

        local dummy_json = test_data_dir .. "/test_on_complete_order.json"
        util.writeToFile("[]", dummy_json)

        local on_complete_success = nil
        local on_complete_merged = nil
        remote.sync_annotations(
          mock_w,
          { file = "dummy.epub" },
          dummy_json,
          function(success, merged_list)
            table.insert(order, "on_complete")
            on_complete_success = success
            on_complete_merged = merged_list
          end,
          false
        )

        assert.are.same(
          { "sync_start", "sync_cb", "upload", "on_complete" },
          order
        )
        assert.is_true(on_complete_success)
        assert.are.same(dummy_merged, on_complete_merged)

        SyncService.sync = old_sync
        annotations.sync_callback = old_sync_cb
      end
    )

    it(
      "calls on_complete(false) if sync execution fails after sync_cb",
      function()
        local old_sync = SyncService.sync
        SyncService.sync = function(server, local_path, callback, silent)
          local cb_res = callback(local_path, local_path, local_path, 200)
          return false
        end

        local annotations =
          require("plugins/AnnotationSync.koplugin/annotations")
        local old_sync_cb = annotations.sync_callback
        annotations.sync_callback = function()
          return true, { { page = 1 } }
        end

        local mock_w = {
          ui = {},
          settings = { sync_server = { url = "http://mock", type = "dropbox" } },
          manager = {
            getSyncCachePath = function()
              return nil
            end,
          },
        }

        local dummy_json = test_data_dir .. "/test_on_complete_fail.json"
        util.writeToFile("[]", dummy_json)

        local on_complete_success = nil
        remote.sync_annotations(
          mock_w,
          { file = "dummy.epub" },
          dummy_json,
          function(success)
            on_complete_success = success
          end,
          false
        )

        assert.is_false(on_complete_success)

        SyncService.sync = old_sync
        annotations.sync_callback = old_sync_cb
      end
    )

    it(
      "passes sdr cached_path to sync_callback and moves tmp cache to sdr post-sync",
      function()
        local old_sync = SyncService.sync
        local received_cached_file = nil
        SyncService.sync = function(server, local_path, callback, silent)
          local tmp_cached = local_path .. ".sync"
          util.writeToFile('{"version":1,"cached":true}', tmp_cached)
          local cb_res = callback(local_path, tmp_cached, local_path, 200)
          return true
        end

        local annotations =
          require("plugins/AnnotationSync.koplugin/annotations")
        local old_sync_cb = annotations.sync_callback
        annotations.sync_callback = function(
          doc,
          local_f,
          cached_f,
          inc_f,
          force,
          code
        )
          received_cached_file = cached_f
          return true, {}
        end

        local mock_w = {
          ui = {},
          settings = { sync_server = { url = "http://mock", type = "dropbox" } },
        }

        local dummy_json = test_data_dir .. "/test_tmp_cache.json"
        local sdr_cache = test_data_dir .. "/test_book.sdr/annotations.sync"
        util.makePath(test_data_dir .. "/test_book.sdr")
        util.writeToFile('{"initial":true}', sdr_cache)
        util.writeToFile("[]", dummy_json)

        remote.sync_annotations(
          mock_w,
          { file = "dummy.epub" },
          dummy_json,
          function() end,
          false,
          sdr_cache
        )

        -- 1. sync_callback should receive the real sdr_cache path, not /tmp cache path
        assert.are.equal(sdr_cache, received_cached_file)

        -- 2. post-sync, the tmp cache file should have been moved to sdr_cache
        assert.is_false(lfs.attributes(dummy_json .. ".sync") ~= nil)
        local f = io.open(sdr_cache, "r")
        local content = f and f:read("*all")
        if f then
          f:close()
        end
        assert.are.equal('{"version":1,"cached":true}', content)

        SyncService.sync = old_sync
        annotations.sync_callback = old_sync_cb
      end
    )

    it("does not overwrite sdr cached_path if sync fails", function()
      local old_sync = SyncService.sync
      SyncService.sync = function(server, local_path, callback, silent)
        local tmp_cached = local_path .. ".sync"
        util.writeToFile('{"corrupted":true}', tmp_cached)
        callback(local_path, tmp_cached, local_path, 200)
        return false
      end

      local annotations = require("plugins/AnnotationSync.koplugin/annotations")
      local old_sync_cb = annotations.sync_callback
      annotations.sync_callback = function()
        return true, {}
      end

      local mock_w = {
        ui = {},
        settings = { sync_server = { url = "http://mock", type = "dropbox" } },
      }

      local dummy_json = test_data_dir .. "/test_fail_cache.json"
      local sdr_cache = test_data_dir .. "/test_book.sdr/annotations_fail.sync"
      util.makePath(test_data_dir .. "/test_book.sdr")
      util.writeToFile('{"initial":true}', sdr_cache)
      util.writeToFile("[]", dummy_json)

      remote.sync_annotations(
        mock_w,
        { file = "dummy.epub" },
        dummy_json,
        function() end,
        false,
        sdr_cache
      )

      -- sdr_cache should remain unchanged
      local f = io.open(sdr_cache, "r")
      local content = f and f:read("*all")
      if f then
        f:close()
      end
      assert.are.equal('{"initial":true}', content)
      -- tmp cache should be cleaned up
      assert.is_false(lfs.attributes(dummy_json .. ".sync") ~= nil)

      SyncService.sync = old_sync
      annotations.sync_callback = old_sync_cb
    end)
  end)
end)
