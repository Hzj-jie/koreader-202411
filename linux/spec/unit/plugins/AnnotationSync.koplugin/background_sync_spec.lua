describe("Background Sync Behavior", function()
  local ReaderUI, UIManager, Trapper, SyncService, Geom
  local AnnotationSyncPlugin, SyncManager, remote, json, test_utils, util, utils
  local readerui, plugin_instance, sync_manager, real_sync
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
    real_sync = SyncService.sync
    json = require("json")
    util = require("util")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
    SyncManager = require("plugins/AnnotationSync.koplugin/manager")
    remote = require("plugins/AnnotationSync.koplugin/remote")
    utils = require("plugins/AnnotationSync.koplugin/utils")

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
    local DataStorage = require("datastorage")

    it(
      "removes successfully synced documents from changed_documents and updates sync timestamp",
      function()
        sync_manager:addToChangedDocumentsFile(readerui.document.file)
        sync_manager:syncPendingDocumentsBg()

        local job = require("pluginshare").backgroundJobs[#require(
          "pluginshare"
        ).backgroundJobs]

        local tmp_json = DataStorage:getTmpDir() .. "/test_bg_sync1.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        util.writeToFile("[]", tmp_json .. ".uploaded")
        job.callback({
          result = {
            file = readerui.document.file,
            json_path = tmp_json,
            success = true,
            uploaded = true,
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
      local tmp_json = DataStorage:getTmpDir() .. "/test_bg_sync2.json"
      util.writeToFile("[]", tmp_json .. ".snapshot")
      util.writeToFile(json.encode(dummy_ann), tmp_json .. ".uploaded")

      job.callback({
        result = {
          file = readerui.document.file,
          json_path = tmp_json,
          success = true,
          uploaded = true,
        },
      })

      assert.is_equal(1, #readerui.annotation.annotations)
      assert.is_equal(
        "Background Synced Annotation",
        readerui.annotation.annotations[1].text
      )
    end)

    it(
      "does not alter active ReaderUI annotations for unrelated inactive synced documents, but updates inactive sidecar",
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
        local dummy_ann = { { text = "Annotation for Leaves", page = "/1/4/2/4" } }
        local tmp_json = DataStorage:getTmpDir() .. "/test_bg_sync3.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        util.writeToFile(json.encode(dummy_ann), tmp_json .. ".uploaded")

        job.callback({
          result = {
            file = inactive_doc,
            json_path = tmp_json,
            success = true,
            uploaded = true,
          },
        })

        assert.is_equal(0, #readerui.annotation.annotations)
        local total, _ = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)

        local sidecar = require("docsettings"):open(inactive_doc)
        local loaded = require("apps/reader/modules/readerannotation").loadFromSettings(sidecar)
        assert.is_equal(1, #loaded)
        assert.is_equal("Annotation for Leaves", loaded[1].text)
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
    local annotations = require("plugins/AnnotationSync.koplugin/annotations")
    local old_sync, old_sync_cb

    before_each(function()
      old_sync = SyncService.sync
      old_sync_cb = annotations.sync_callback
    end)

    after_each(function()
      SyncService.sync = old_sync
      annotations.sync_callback = old_sync_cb
    end)

    it(
      "calls on_complete strictly after sync finishes, passing captured merged_list",
      function()
        local order = {}
        SyncService.sync = function(server, local_path, callback, silent, finish_cb)
          table.insert(order, "sync_start")
          local cb_res = callback(local_path, local_path, local_path, 200)
          table.insert(order, "upload")
          if finish_cb then
            finish_cb(true)
          end
          return true
        end

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
      end
    )

    it(
      "calls on_complete(false) if sync execution fails after sync_cb",
      function()
        SyncService.sync = function(server, local_path, callback, silent, finish_cb)
          local cb_res = callback(local_path, local_path, local_path, 200)
          if finish_cb then
            finish_cb(false)
          end
          return false
        end

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
      end
    )

    it(
      "passes sdr cached_path to sync_callback and passes uploaded_json to on_complete without mutating sdr directly",
      function()
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

        annotations.sync_callback = function(
          local_f,
          cached_f,
          inc_f,
          force,
          code
        )
          received_cached_file = cached_f
          util.writeToFile('{"uploaded":true}', local_f)
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

        local on_complete_uploaded = nil
        remote.sync_annotations(
          mock_w,
          dummy_json,
          function(success, merged, uploaded_json)
            on_complete_uploaded = uploaded_json
          end,
          false,
          sdr_cache
        )

        -- 1. sync_callback should receive the real sdr_cache path, not /tmp cache path
        assert.are.equal(sdr_cache, received_cached_file)

        -- 2. post-sync, sdr_cache must remain untouched (caller promotes after apply)
        local f = io.open(sdr_cache, "r")
        local content = f and f:read("*all")
        if f then
          f:close()
        end
        assert.are.equal('{"initial":true}', content)
        assert.are.equal('{"uploaded":true}', on_complete_uploaded)
      end
    )

    it("does not overwrite sdr cached_path if sync fails", function()
      SyncService.sync = function(server, local_path, callback, silent, finish_cb)
        local tmp_cached = local_path .. ".sync"
        util.writeToFile('{"corrupted":true}', tmp_cached)
        callback(local_path, tmp_cached, local_path, 200)
        if finish_cb then
          finish_cb(false)
        end
        return false
      end

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
      "Case 13: sync_annotations, finish_cb(true) -> on_complete(true, merged, uploaded_json), sdr_cache untouched",
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
        annotations.sync_callback = function(local_f)
          util.writeToFile('{"uploaded":true}', local_f)
          return true, dummy_merged
        end

        local comp_res, comp_data, comp_uploaded
        remote.sync_annotations(mock_w, dummy_json, function(success, merged, uploaded_json)
          comp_res = success
          comp_data = merged
          comp_uploaded = uploaded_json
        end, false, sdr_cache)

        assert.is_true(comp_res)
        assert.are.same(dummy_merged, comp_data)
        assert.are.equal('{"uploaded":true}', comp_uploaded)

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

  describe("End-to-end background 3-way merge integration", function()
    local BackgroundJobs, ffiutil, DocSettings, NetworkMgr
    local remote_store = {}
    local old_insertKeyed, old_sync, old_cloudstorage, old_server, old_isOnline

    local function basename(p)
      return p:match("([^/]+)$")
    end

    local function texts(list)
      local out = {}
      for _, v in pairs(list or {}) do
        local t = v.text
        if v.note then
          t = t .. "[" .. v.note .. "]"
        end
        table.insert(out, t .. (v.deleted and "(DELETED)" or ""))
      end
      table.sort(out)
      return table.concat(out, ", ")
    end

    local function new_doc(tag)
      local doc = test_data_dir .. "/" .. tag .. ".epub"
      ffiutil.copyFile("spec/front/unit/data/juliet.epub", doc)
      return doc, sync_manager:_getAnnotationFilename(doc)
    end

    local function is_pending(file)
      local _, docs = sync_manager:getPendingChangedDocuments()
      return docs and docs[file] == true
    end

    local function encode(list)
      return json.encode(list)
    end

    local function copy(t)
      return util.tableDeepCopy(t)
    end

    local last_child_res
    local function fork_like(during, skip_callback)
      BackgroundJobs.insertKeyed = function(job)
        local res = false
        local ok, ret = pcall(job.action)
        if ok then
          res = ret
        end
        last_child_res = res
        if during then
          during()
        end
        if not skip_callback then
          job.result = res
          job.callback(job)
        end
        return true
      end
    end

    local function hl(doc, p, text, ts)
      return {
        page = doc:getPageXPointer(p),
        pos0 = doc:getPageXPointer(p),
        pos1 = doc:getPageXPointer(p + 1),
        text = text,
        datetime = ts,
        drawer = "lighten",
        color = "yellow",
      }
    end

    local function mk(n, text, ts)
      local p0 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().0"
      return {
        page = p0,
        pos0 = p0,
        pos1 = (p0:gsub("%.0$", ".20")),
        text = text,
        datetime = ts or "2026-01-01 10:00:00",
        drawer = "lighten",
      }
    end

    local function remove_item(list, text)
      for i, v in ipairs(list) do
        if v.text == text then
          return table.remove(list, i)
        end
      end
    end

    local function find_item(list, text)
      for _, v in ipairs(list) do
        if v.text == text then
          return v
        end
      end
    end

    local old_show

    before_each(function()
      NetworkMgr = require("ui/network/manager")
      old_isOnline = NetworkMgr.isOnline
      NetworkMgr.isOnline = function()
        return true
      end

      BackgroundJobs = require("background_jobs")
      old_insertKeyed = BackgroundJobs.insertKeyed
      ffiutil = require("ffi/util")
      DocSettings = require("frontend/docsettings")

      old_cloudstorage = readerui.cloudstorage
      readerui.cloudstorage = nil

      old_sync = SyncService.sync
      SyncService.sync = real_sync

      old_show = UIManager.show
      UIManager.show = function(self, w, ...)
        if type(w) == "table" and type(w.text) == "string" then
          return
        end
        return old_show(self, w, ...)
      end

      package.loaded["apps/cloudstorage/dropboxapi"] = {
        downloadFile = function(_, url, _token, dest)
          local content = remote_store[basename(url)]
          if not content then
            return 409
          end
          util.writeToFile(content, dest)
          return 200, "etag-1"
        end,
        uploadFile = function(_, _url_base, _token, file_path, _etag, _overwrite)
          local f = io.open(file_path, "r")
          remote_store[basename(file_path)] = f:read("*a")
          f:close()
          return 200
        end,
      }

      old_server = plugin_instance.settings.sync_server
      rawset(plugin_instance.settings, "sync_server", {
        type = "dropbox",
        url = "/koreader",
        password = "token",
        address = "",
      })

      remote_store = {}
      readerui.annotation.annotations = {}
      os.remove(sync_manager:changedDocumentsFile())
    end)

    after_each(function()
      NetworkMgr.isOnline = old_isOnline
      BackgroundJobs.insertKeyed = old_insertKeyed
      readerui.cloudstorage = old_cloudstorage
      SyncService.sync = old_sync
      UIManager.show = old_show
      package.loaded["apps/cloudstorage/dropboxapi"] = nil
      plugin_instance.settings.sync_server = old_server
      readerui.annotation.annotations = {}
    end)

    it(
      "inactive doc gains remote additions, advances .sync, next sync preserves them",
      function()
        local doc, name = new_doc("inactive_doc")
        local function mk(n, text, ts)
          local p0 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().0"
          return {
            page = p0,
            pos0 = p0,
            pos1 = (p0:gsub("%.0$", ".20")),
            text = text,
            datetime = ts,
            drawer = "lighten",
          }
        end
        local L = mk(1, "L_local", "2026-01-01 10:00:00")
        local R = mk(2, "R_remote", "2026-01-02 10:00:00")

        local ds = DocSettings:open(doc)
        ds:save("annotations", { L })
        ds:flush()
        remote_store[name] = encode({ R })

        sync_manager:addToChangedDocumentsFile(doc)
        fork_like()
        sync_manager:syncPendingDocumentsBg()

        -- Sidecar must contain both L and R
        local side1 = DocSettings:open(doc):readTable("annotations")
        assert.are.equal(2, #side1)
        local texts1 = { side1[1].text, side1[2].text }
        table.sort(texts1)
        assert.are.same({ "L_local", "R_remote" }, texts1)

        -- .sync merge base must contain both L and R
        local cache1 = utils.read_json(sync_manager:getSyncCachePath(doc))
        assert.are.equal(2, #cache1)

        -- Document is no longer pending
        assert.is_false(is_pending(doc))

        -- Next sync: add L2 locally, ensure R is NOT tombstoned
        local L2 = mk(3, "L2_local_later", "2026-01-03 10:00:00")
        table.insert(side1, L2)
        ds = DocSettings:open(doc)
        ds:save("annotations", side1)
        ds:flush()

        sync_manager:addToChangedDocumentsFile(doc)
        sync_manager:syncPendingDocumentsBg()

        local remote_after = json.decode(remote_store[name])
        assert.are.equal(3, #remote_after)
        for _, item in ipairs(remote_after) do
          assert.is_nil(item.deleted)
        end
      end
    )

    it(
      "open book edits made during background sync survive and stay pending",
      function()
        local doc = readerui.document
        local file = doc.file
        local name = sync_manager:_getAnnotationFilename(file)
        local T0, T1 = "2026-01-01 10:00:00", "2026-01-03 10:00:00"
        local K = hl(doc, 3, "K_keep", T0)
        local A = hl(doc, 5, "A_deleted_remotely", T0)
        local A_tomb = copy(A)
        A_tomb.deleted = true
        A_tomb.datetime_updated = "2026-01-05 10:00:00"
        local D = hl(doc, 7, "D_deleted_during_job", T0)
        local X = hl(doc, 9, "X_edit", T0)
        local P = hl(doc, 11, "P_added_before_fork", T1)
        local Q = hl(doc, 13, "Q_added_before_fork_deleted_during_job", T1)
        local R = hl(doc, 15, "R_remote", "2026-01-04 10:00:00")

        util.writeToFile(encode({ K, A, D, X }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ K, A_tomb, D, X, R })
        readerui.annotation.annotations = copy({ K, A, D, X, P, Q })
        readerui.annotation:updatePageNumbers(true)
        sync_manager:addToChangedDocumentsFile(file)

        -- During the job, user edits X's note, removes D and Q, adds H
        fork_like(function()
          local live = readerui.annotation.annotations
          local d = remove_item(live, "D_deleted_during_job")
          local q = remove_item(live, "Q_added_before_fork_deleted_during_job")
          find_item(live, "X_edit").note = "new_note"
          local H = hl(doc, 17, "H_during", "2026-01-04 12:00:00")
          readerui.annotation:addItem(H)
          plugin_instance:onAnnotationsModified({ d, q, H })
        end)

        sync_manager:syncPendingDocumentsBg()

        -- Live UI must have K_keep, P_added_before_fork, R_remote, H_during, and X_edit with new_note
        local live = readerui.annotation.annotations
        assert.are.equal(5, #live)
        local notes_or_texts = {}
        for _, ann in ipairs(live) do
          table.insert(notes_or_texts, ann.note or ann.text)
        end
        table.sort(notes_or_texts)
        assert.are.same(
          { "H_during", "K_keep", "P_added_before_fork", "R_remote", "new_note" },
          notes_or_texts
        )

        -- Document must remain pending in changed_documents!
        assert.is_true(is_pending(file))

        -- Next sync: performs normal sync and uploads H and X with new_note, plus tombstones for A, D, Q
        sync_manager:syncDocument(readerui.document, false)

        local remote_after = json.decode(remote_store[name])
        local active_remote = {}
        for _, ann in ipairs(remote_after) do
          if not ann.deleted then
            table.insert(active_remote, ann.note or ann.text)
          end
        end
        table.sort(active_remote)
        assert.are.same(
          { "H_during", "K_keep", "P_added_before_fork", "R_remote", "new_note" },
          active_remote
        )
      end
    )

    it(
      "lost callback does not promote .sync base and subsequent sync keeps remote additions",
      function()
        local doc, name = new_doc("lost_callback")
        local L0 = {
          page = "/body/DocFragment[3]/body/p[1]/text().0",
          pos0 = "/body/DocFragment[3]/body/p[1]/text().0",
          pos1 = "/body/DocFragment[3]/body/p[1]/text().20",
          text = "L0_base",
          drawer = "lighten",
          datetime = "2026-01-01 10:00:00",
        }
        local R = copy(L0)
        R.page = "/body/DocFragment[3]/body/p[2]/text().0"
        R.pos0, R.pos1 = R.page, "/body/DocFragment[3]/body/p[2]/text().20"
        R.text, R.datetime = "R_remote", "2026-01-02 10:00:00"

        local ds = DocSettings:open(doc)
        ds:save("annotations", { L0 })
        ds:flush()
        util.writeToFile(encode({ L0 }), sync_manager:getSyncCachePath(doc))
        remote_store[name] = encode({ L0, R })

        sync_manager:addToChangedDocumentsFile(doc)

        -- Callback is lost / skipped (simulating child finished but parent died/dropped)
        fork_like(nil, true)
        sync_manager:syncPendingDocumentsBg()

        -- Child itself must have succeeded and reported uploaded
        assert.is_table(last_child_res)
        assert.is_true(last_child_res.success)
        assert.is_true(last_child_res.uploaded)
        assert.is_not_nil(last_child_res.json_path)
        assert.is_nil(last_child_res.snapshot_json)
        assert.is_nil(last_child_res.uploaded_json)

        -- .sync file must not have been promoted (remains L0)
        local cache_content = utils.read_json(sync_manager:getSyncCachePath(doc))
        assert.are.equal(1, #cache_content)
        assert.are.equal("L0_base", cache_content[1].text)

        -- Document remains pending
        assert.is_true(is_pending(doc))

        -- Next sync runs to completion: R must survive
        BackgroundJobs.insertKeyed = old_insertKeyed
        sync_manager:syncDocument(doc, false)

        local remote_after = json.decode(remote_store[name])
        assert.are.equal(2, #remote_after)
        for _, ann in ipairs(remote_after) do
          assert.is_nil(ann.deleted)
        end
        local side_after = DocSettings:open(doc):readTable("annotations")
        assert.are.equal(2, #side_after)
      end
    )

    it(
      "highlight added during no-op background sync survives and remains pending",
      function()
        local doc = readerui.document
        local file = doc.file
        os.remove(sync_manager:getSyncCachePath(file))
        sync_manager:addToChangedDocumentsFile(file)

        fork_like(function()
          local H = hl(doc, 19, "H_during_noop")
          readerui.annotation:addItem(H)
          plugin_instance:onAnnotationsModified({ H })
        end)

        sync_manager:syncPendingDocumentsBg()

        assert.are.equal(1, #readerui.annotation.annotations)
        assert.are.equal("H_during_noop", readerui.annotation.annotations[1].text)
        assert.is_true(is_pending(file))
      end
    )

    it(
      "book reopened in a new ReaderUI while its job runs",
      function()
        local old_register = readerui.menu.registerToMainMenu
        readerui.menu.registerToMainMenu = function() end
        finally(function()
          plugin_instance:init()
          readerui.menu.registerToMainMenu = old_register
        end)

        local doc = readerui.document
        local file = doc.file
        local name = sync_manager:_getAnnotationFilename(file)
        local A = hl(doc, 21, "A_existing", "2026-01-01 10:00:00")
        local R = hl(doc, 23, "R_from_other_device", "2026-01-02 10:00:00")

        local fm_ui = { menu = { registerToMainMenu = function() end } }
        local fm_plugin = AnnotationSyncPlugin:new({
          ui = fm_ui,
          plugin_id = plugin_instance.plugin_id,
          path = "plugins/AnnotationSync.koplugin",
        })
        fm_plugin:init()

        local ds = DocSettings:open(file)
        ds:save("annotations", { A })
        ds:flush()
        readerui.annotation.annotations = copy({ A })
        readerui.annotation:updatePageNumbers(true)
        util.writeToFile(encode({ A }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ A, R })
        sync_manager:addToChangedDocumentsFile(file)

        fork_like(function()
          plugin_instance:init()
          local H = hl(doc, 25, "H_added_during_job")
          readerui.annotation:addItem(H)
          plugin_instance:onAnnotationsModified({ H })
        end)

        fm_plugin.manager:syncPendingDocumentsBg()

        assert.are.equal(3, #readerui.annotation.annotations)
        assert.are.equal(
          "A_existing, H_added_during_job, R_from_other_device",
          texts(readerui.annotation.annotations)
        )
        assert.are.equal(
          "A_existing, H_added_during_job, R_from_other_device",
          texts(DocSettings:open(file):readTable("annotations"))
        )
        assert.is_true(is_pending(file))
      end
    )

    it(
      "offline-queued sync uses the book opened before the network came back",
      function()
        local NetworkListener = require("ui/network/networklistener")
        local NetworkMgr = require("ui/network/manager")
        local old_register = readerui.menu.registerToMainMenu
        readerui.menu.registerToMainMenu = function() end
        finally(function()
          plugin_instance:init()
          readerui.menu.registerToMainMenu = old_register
        end)

        local doc = readerui.document
        local file = doc.file
        local name = sync_manager:_getAnnotationFilename(file)
        local A = hl(doc, 21, "A_existing", "2026-01-01 10:00:00")
        local R = hl(doc, 23, "R_from_other_device", "2026-01-02 10:00:00")

        local fm_ui = { menu = { registerToMainMenu = function() end } }
        local fm_plugin = AnnotationSyncPlugin:new({
          ui = fm_ui,
          plugin_id = plugin_instance.plugin_id,
          path = "plugins/AnnotationSync.koplugin",
        })
        fm_plugin:init()

        local ds = DocSettings:open(file)
        ds:save("annotations", { A })
        ds:flush()
        readerui.annotation.annotations = copy({ A })
        readerui.annotation:updatePageNumbers(true)
        util.writeToFile(encode({ A }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ A, R })
        sync_manager:addToChangedDocumentsFile(file)

        NetworkMgr.isOnline = function()
          return false
        end

        fm_plugin.manager:syncPendingDocumentsBg()
        assert.is_equal("0 / 1", NetworkListener:countsOfPendingJobs())

        plugin_instance:init()

        local H = hl(doc, 25, "H_added_offline")
        readerui.annotation:addItem(H)
        plugin_instance:onAnnotationsModified({ H })

        NetworkMgr.isOnline = function()
          return true
        end

        fork_like()
        NetworkListener:onNetworkOnline()
        fastforward_ui_events()

        assert.are.equal(3, #readerui.annotation.annotations)
        assert.are.equal(
          "A_existing, H_added_offline, R_from_other_device",
          texts(readerui.annotation.annotations)
        )
        assert.are.equal(
          "A_existing, H_added_offline, R_from_other_device",
          texts(DocSettings:open(file):readTable("annotations"))
        )
        local remote_after = json.decode(remote_store[name])
        assert.are.equal(3, #remote_after)
        assert.are.equal(
          "A_existing, H_added_offline, R_from_other_device",
          texts(remote_after)
        )
        assert.is_false(is_pending(file))
      end
    )

    it(
      "foreground/background sync of open book flushes to disk so disk has remote additions without manual save",
      function()
        local doc = readerui.document
        local file = doc.file
        local name = sync_manager:_getAnnotationFilename(file)
        local A = hl(doc, 27, "A_flush", "2026-01-01 10:00:00")
        local R = hl(doc, 29, "R_flush_remote", "2026-01-02 10:00:00")

        local ds = DocSettings:open(file)
        ds:save("annotations", { A })
        ds:flush()
        readerui.annotation.annotations = copy({ A })
        readerui.annotation:updatePageNumbers(true)
        util.writeToFile(encode({ A }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ A, R })
        sync_manager:addToChangedDocumentsFile(file)

        fork_like()
        sync_manager:syncPendingDocumentsBg()

        -- Without calling readerui:saveSettings() or readerui:onClose(),
        -- a fresh DocSettings:open reads directly from disk.
        -- Flushing in applySyncedAnnotations ensures R is already on disk.
        local fresh_ds = DocSettings:open(file)
        local disk_anns = fresh_ds:readTable("annotations")
        assert.are.equal(2, #disk_anns)
        local disk_texts = { disk_anns[1].text, disk_anns[2].text }
        table.sort(disk_texts)
        assert.are.same({ "A_flush", "R_flush_remote" }, disk_texts)

        -- .sync cache is also promoted
        local cached = utils.read_json(sync_manager:getSyncCachePath(file))
        assert.are.equal(2, #cached)
      end
    )

    it(
      "skips apply and cleans pending when book was deleted during background job",
      function()
        local doc, name = new_doc("deleted_during_job")
        local function mk(n, text, ts)
          local p0 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().0"
          return {
            page = p0,
            pos0 = p0,
            pos1 = (p0:gsub("%.0$", ".20")),
            text = text,
            datetime = ts,
            drawer = "lighten",
          }
        end
        local L = mk(1, "L_del", "2026-01-01 10:00:00")
        local R = mk(2, "R_del", "2026-01-02 10:00:00")

        local ds = DocSettings:open(doc)
        ds:save("annotations", { L })
        ds:flush()
        remote_store[name] = encode({ L, R })
        sync_manager:addToChangedDocumentsFile(doc)

        local lfs = require("libs/libkoreader-lfs")
        local sdr_dir = DocSettings:getSidecarDir(doc)

        fork_like(function()
          -- Simulate user deleting book and its sidecar directory while child runs
          os.remove(doc)
          os.execute("rm -rf " .. sdr_dir)
        end)

        sync_manager:syncPendingDocumentsBg()

        -- .sdr directory must not have been recreated
        assert.is_nil(lfs.attributes(sdr_dir, "mode"))

        -- Document is pruned from changed documents
        assert.is_false(is_pending(doc))
      end
    )

    it(
      "child result carries only status and tmp location without annotation text, preserving tmp files for callback",
      function()
        local doc, name = new_doc("child_result_shape")
        local H = mk(1, "H_child_shape")
        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()
        sync_manager:addToChangedDocumentsFile(doc)

        local during_snapshot_exists = false
        local during_uploaded_exists = false
        fork_like(function()
          if last_child_res and last_child_res.json_path then
            during_snapshot_exists = util.fileExists(last_child_res.json_path .. ".snapshot")
            during_uploaded_exists = util.fileExists(last_child_res.json_path .. ".uploaded")
          end
        end)

        sync_manager:syncPendingDocumentsBg()

        assert.is_table(last_child_res)
        assert.are.equal(doc, last_child_res.file)
        assert.is_not_nil(last_child_res.json_path)
        assert.is_true(last_child_res.success)
        assert.is_true(last_child_res.uploaded)
        assert.is_nil(last_child_res.snapshot_json)
        assert.is_nil(last_child_res.uploaded_json)

        assert.is_true(during_snapshot_exists)
        assert.is_true(during_uploaded_exists)

        assert.is_false(util.fileExists(last_child_res.json_path .. ".snapshot"))
        assert.is_false(util.fileExists(last_child_res.json_path .. ".uploaded"))
      end
    )

    it(
      "cleans all child tmp files after callback when sync uploads changes",
      function()
        local doc, name = new_doc("cleanup_upload")
        local H = mk(1, "H_upload")
        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()
        sync_manager:addToChangedDocumentsFile(doc)

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:syncPendingDocumentsBg()

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )

    it(
      "cleans all child tmp files after callback when sync has nothing to upload",
      function()
        local doc, name = new_doc("cleanup_noop")
        sync_manager:addToChangedDocumentsFile(doc)

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:syncPendingDocumentsBg()

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )

    it(
      "cleans all child tmp files after callback when sync fails",
      function()
        local doc, name = new_doc("cleanup_failed")
        local H = mk(1, "H_fail")
        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()
        sync_manager:addToChangedDocumentsFile(doc)

        SyncService.sync = function(server, path, sync_cb, is_silent, finish_cb)
          if finish_cb then
            finish_cb(false)
          end
        end

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:syncPendingDocumentsBg()

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )

    it(
      "cleans all child tmp files after callback when book is deleted during job",
      function()
        local doc, name = new_doc("cleanup_deleted_book")
        local H = mk(1, "H_del_clean")
        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()
        sync_manager:addToChangedDocumentsFile(doc)

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
          os.remove(doc)
          local sdr_dir = DocSettings:getSidecarDir(doc)
          os.execute("rm -rf " .. sdr_dir)
        end)
        sync_manager:syncPendingDocumentsBg()

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )
  end)
end)
