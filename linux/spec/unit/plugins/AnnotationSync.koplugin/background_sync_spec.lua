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
      "does not broadcast FlushSettings during background sync to avoid loop",
      function()
        local flush_broadcasted = false
        local old_broadcast = UIManager.broadcastEvent
        UIManager.broadcastEvent = function(self, event, ...)
          local ev_name = type(event) == "string" and event
            or (event and event.name)
          if ev_name == "FlushSettings" then
            flush_broadcasted = true
          end
          return old_broadcast(self, event, ...)
        end

        sync_manager:addToChangedDocumentsFile(readerui.document.file)
        sync_manager:syncPendingDocumentsBg()

        assert.is_false(flush_broadcasted)
        UIManager.broadcastEvent = old_broadcast
      end
    )

    it(
      "does not broadcast FlushSettings during single document sync",
      function()
        local flush_broadcasted = false
        local old_broadcast = UIManager.broadcastEvent
        UIManager.broadcastEvent = function(self, event, ...)
          local ev_name = type(event) == "string" and event
            or (event and event.name)
          if ev_name == "FlushSettings" then
            flush_broadcasted = true
          end
          return old_broadcast(self, event, ...)
        end

        sync_manager:syncDocument(readerui.document, true)

        assert.is_false(flush_broadcasted)
        UIManager.broadcastEvent = old_broadcast
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
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          sync_called_silent = is_silent
          local res = callback(local_path, local_path, local_path)
          if finish_cb then
            finish_cb(res)
          end
          return res
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
      "suppresses InfoMessage when cloud destination server is missing in silent mode",
      function()
        local old_show = UIManager.show
        local show_called = false
        UIManager.show = function(self_ui, widget)
          show_called = true
        end

        local mock_w = {
          settings = {},
        }

        local dummy_json = test_data_dir .. "/test_silent_dest.json"
        remote.sync_annotations(mock_w, dummy_json, function() end, false)

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
        SyncService.sync = function(server, local_path, callback, silent, finish_cb)
          table.insert(order, "sync_start")
          local cb_res = callback(local_path, local_path, local_path, 200)
          table.insert(order, "upload")
          if finish_cb then
            finish_cb(true)
          end
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
        SyncService.sync = function(server, local_path, callback, silent, finish_cb)
          local cb_res = callback(local_path, local_path, local_path, 200)
          if finish_cb then
            finish_cb(false)
          end
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
        remote.sync_annotations(mock_w, dummy_json, function(success)
          on_complete_success = success
        end, false)

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
        SyncService.sync = function(server, local_path, callback, silent, finish_cb)
          local tmp_cached = local_path .. ".sync"
          util.writeToFile('{"version":1,"cached":true}', tmp_cached)
          local cb_res = callback(local_path, tmp_cached, local_path, 200)
          if finish_cb then
            finish_cb(true)
          end
          return true
        end

        local annotations =
          require("plugins/AnnotationSync.koplugin/annotations")
        local old_sync_cb = annotations.sync_callback
        annotations.sync_callback = function(
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
      SyncService.sync = function(server, local_path, callback, silent, finish_cb)
        local tmp_cached = local_path .. ".sync"
        util.writeToFile('{"corrupted":true}', tmp_cached)
        callback(local_path, tmp_cached, local_path, 200)
        if finish_cb then
          finish_cb(false)
        end
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

  describe("remote.sync_annotations finish_cb contract (N5)", function()
    local annotations = require("plugins/AnnotationSync.koplugin/annotations")
    local old_sync, old_sync_cb, old_show
    local dummy_json, sdr_cache
    local mock_w

    before_each(function()
      old_sync = SyncService.sync
      old_sync_cb = annotations.sync_callback
      old_show = UIManager.show

      mock_w = {
        ui = {},
        settings = { sync_server = { url = "http://mock", type = "dropbox" } },
        manager = {
          getSyncCachePath = function()
            return nil
          end,
        },
      }
      dummy_json = test_data_dir .. "/test_n5_dummy.json"
      sdr_cache = test_data_dir .. "/test_n5_book.sdr/annotations.sync"
      util.makePath(test_data_dir .. "/test_n5_book.sdr")
      util.writeToFile('{"initial":true}', sdr_cache)
      util.writeToFile("[]", dummy_json)
    end)

    after_each(function()
      SyncService.sync = old_sync
      annotations.sync_callback = old_sync_cb
      UIManager.show = old_show
      os.remove(dummy_json)
      os.remove(dummy_json .. ".temp")
      os.remove(dummy_json .. ".sync")
      os.remove(sdr_cache)
    end)

    it(
      "Case 13: sync_annotations, finish_cb(true) -> on_complete(true, merged), .sync copied to cached_path",
      function()
        local dummy_merged = { { page = 1, text = "merged_item" } }
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          local tmp_sync = local_path .. ".sync"
          util.writeToFile('{"uploaded":true}', tmp_sync)
          callback(local_path, tmp_sync, local_path, 200)
          if finish_cb then
            finish_cb(true)
          end
          return true
        end
        annotations.sync_callback = function()
          return true, dummy_merged
        end

        local comp_res, comp_data
        remote.sync_annotations(mock_w, dummy_json, function(success, merged)
          comp_res = success
          comp_data = merged
        end, false, sdr_cache)

        assert.is_true(comp_res)
        assert.are.same(dummy_merged, comp_data)

        local f = io.open(sdr_cache, "r")
        local content = f and f:read("*a")
        if f then
          f:close()
        end
        assert.are.equal('{"uploaded":true}', content)
        assert.is_nil(io.open(dummy_json .. ".sync", "r"))
        assert.is_nil(io.open(dummy_json, "r"))
      end
    )

    it(
      "Case 14: finish_cb(nil) (both sides empty) -> on_complete(true, ...), cached_path not replaced",
      function()
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          callback(local_path, local_path .. ".sync", local_path, 200)
          if finish_cb then
            finish_cb(nil)
          end
          return nil
        end
        annotations.sync_callback = function()
          return true, {}
        end

        local comp_res, comp_data
        remote.sync_annotations(mock_w, dummy_json, function(success, merged)
          comp_res = success
          comp_data = merged
        end, false, sdr_cache)

        assert.is_true(comp_res)
        assert.are.same({}, comp_data)

        local f = io.open(sdr_cache, "r")
        local content = f and f:read("*a")
        if f then
          f:close()
        end
        assert.are.equal('{"initial":true}', content)
        assert.is_nil(io.open(dummy_json, "r"))
      end
    )

    it(
      "Case 15: finish_cb(false) -> on_complete(false, ...), cached_path not replaced",
      function()
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          local tmp_sync = local_path .. ".sync"
          util.writeToFile('{"fail":true}', tmp_sync)
          callback(local_path, tmp_sync, local_path, 200)
          if finish_cb then
            finish_cb(false)
          end
          return false
        end
        annotations.sync_callback = function()
          return false, nil
        end

        local comp_res, comp_data
        remote.sync_annotations(mock_w, dummy_json, function(success, merged)
          comp_res = success
          comp_data = merged
        end, false, sdr_cache)

        assert.is_false(comp_res)

        local f = io.open(sdr_cache, "r")
        local content = f and f:read("*a")
        if f then
          f:close()
        end
        assert.are.equal('{"initial":true}', content)
        assert.is_nil(io.open(dummy_json .. ".sync", "r"))
        assert.is_nil(io.open(dummy_json, "r"))
      end
    )

    it(
      "Case 16: SyncService postpones (mock never calls finish_cb) -> assert fires, on_complete(false), error rethrown, tmp cleaned",
      function()
        local tmp_temp = dummy_json .. ".temp"
        local tmp_sync = dummy_json .. ".sync"
        util.writeToFile("temp_data", tmp_temp)
        util.writeToFile("sync_data", tmp_sync)

        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          return nil
        end

        local comp_called = false
        local comp_res = nil
        local on_complete = function(success)
          comp_called = true
          comp_res = success
        end

        local ok, err = pcall(function()
          remote.sync_annotations(mock_w, dummy_json, on_complete, false, sdr_cache)
        end)

        assert.is_false(ok)
        assert.is_not_nil(err:find("AnnotationSync: SyncService postponed the sync"))
        assert.is_true(comp_called)
        assert.is_false(comp_res)

        assert.is_nil(io.open(dummy_json, "r"))
        assert.is_nil(io.open(tmp_temp, "r"))
        assert.is_nil(io.open(tmp_sync, "r"))
      end
    )

    it(
      "Case 17: No sync_server -> on_complete(false), message if not silent, log line if silent",
      function()
        local no_server_w = {
          ui = {},
          settings = { sync_server = nil },
        }

        local shown_widget = nil
        UIManager.show = function(self, widget)
          shown_widget = widget
        end

        local comp_res_loud = nil
        remote.sync_annotations(no_server_w, dummy_json, function(res)
          comp_res_loud = res
        end, true, sdr_cache)

        assert.is_false(comp_res_loud)
        assert.is_not_nil(shown_widget)
        assert.is_not_nil(shown_widget.text:find("No cloud destination set in settings"))

        shown_widget = nil
        local logger = require("logger")
        local old_warn = logger.warn
        finally(function()
          logger.warn = old_warn
        end)
        local warned_msg = nil
        logger.warn = function(fmt, ...)
          warned_msg = string.format(fmt, ...)
        end

        util.writeToFile("[]", dummy_json)
        local comp_res_silent = nil
        remote.sync_annotations(no_server_w, dummy_json, function(res)
          comp_res_silent = res
        end, false, sdr_cache)

        assert.is_false(comp_res_silent)
        assert.is_nil(shown_widget)
        assert.is_not_nil(warned_msg)
        assert.is_not_nil(warned_msg:find("No cloud destination set in settings"))
      end
    )

    it(
      "skips remote sync and cleans tmp when network is connected but not online (N2)",
      function()
        local NetworkMgr = require("ui/network/manager")
        local old_isConnected = NetworkMgr.isConnected
        local old_isOnline = NetworkMgr.isOnline
        finally(function()
          NetworkMgr.isConnected = old_isConnected
          NetworkMgr.isOnline = old_isOnline
        end)
        NetworkMgr.isConnected = function()
          return true
        end
        NetworkMgr.isOnline = function()
          return false
        end

        local dummy_json = test_data_dir .. "/n2_connected_not_online.json"
        util.writeToFile("[]", dummy_json)
        local sync_called = false
        local old_sync = SyncService.sync
        finally(function()
          SyncService.sync = old_sync
        end)
        SyncService.sync = function()
          sync_called = true
        end

        local comp_called, comp_res = false, nil
        remote.sync_annotations(mock_w, dummy_json, function(res)
          comp_called = true
          comp_res = res
        end, false, sdr_cache)

        assert.is_false(sync_called)
        assert.is_true(comp_called)
        assert.is_false(comp_res)
        assert.is_nil(io.open(dummy_json, "r"))
      end
    )
  end)
end)
