describe("Background Sync Behavior", function()
  local UIManager, SyncService
  local AnnotationSyncPlugin, remote, json, test_utils, util, utils, DataStorage, dump
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
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    real_sync = SyncService.sync
    json = require("json")
    util = require("util")
    DataStorage = require("datastorage")
    dump = require("dump")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
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
    sync_manager.running = nil
  end)

  after_each(function()
    os.remove(sync_manager:changedDocumentsFile())
    local jobs = require("pluginshare").backgroundJobs
    for k in pairs(jobs) do
      jobs[k] = nil
    end
    require("background_jobs").clearKeys()
    sync_manager.running = nil
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

      sync_manager:_dispatchNextSync()

      assert.is_equal(initial_count, #jobs)
    end)

    it("prunes missing files on disk immediately in main thread", function()
      local jobs = require("pluginshare").backgroundJobs
      local initial_count = #jobs

      local missing_file = "/nonexistent/path/missing_book.epub"
      sync_manager:addToChangedDocumentsFile(missing_file)
      sync_manager:addToChangedDocumentsFile(readerui.document.file)

      -- Missing file is pruned immediately
      local _, changed = sync_manager:getPendingChangedDocuments()
      assert.falsy(util.arrayContains(changed, missing_file))
      assert.truthy(util.arrayContains(changed, readerui.document.file))

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
    local function track_dispatched_file()
      local dispatched = {}
      local old_startSync = sync_manager._startSync
      sync_manager._startSync = function(self_m, file)
        dispatched.file = file
        return old_startSync(self_m, file)
      end
      finally(function()
        sync_manager._startSync = old_startSync
      end)
      return setmetatable(dispatched, {
        __call = function(self)
          return self.file
        end,
      })
    end

    it(
      "registers an asap fork job in pluginshare.backgroundJobs via insertKeyed",
      function()
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:addToChangedDocumentsFile(readerui.document.file)

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
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:addToChangedDocumentsFile(readerui.document.file)
        sync_manager:addToChangedDocumentsFile(readerui.document.file)

        -- Only 1 job is inserted thanks to sync queue dedup
        assert.is_equal(initial_count + 1, #jobs)
      end
    )

    it(
      "deduplicates queued background sync requests for the same pending book",
      function()
        local doc = readerui.document.file
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:addToChangedDocumentsFile(doc)

        -- Job 1 is forked
        assert.is_equal(initial_count + 1, #jobs)
        local job1 = jobs[#jobs]

        -- Trigger background sync twice more while job 1 is in-flight
        sync_manager:addToChangedDocumentsFile(doc)
        sync_manager:addToChangedDocumentsFile(doc)

        -- Still only 1 job has been forked
        assert.is_equal(initial_count + 1, #jobs)

        -- Completing job 1 as failure leaves book pending and pauses queue
        job1.result = { file = doc, success = false }
        job1.callback(job1)
        assert.is_equal(initial_count + 1, #jobs)

        -- Triggering next sync pass forks job 2 (retry)
        sync_manager:_dispatchNextSync()
        assert.is_equal(initial_count + 2, #jobs)
        local job2 = jobs[#jobs]

        -- Completing job 2 as failure pauses queue
        job2.result = { file = doc, success = false }
        job2.callback(job2)
        assert.is_equal(initial_count + 2, #jobs)
      end
    )

    it(
      "enforces a single in-flight background job for a book when triggered open and closed",
      function()
        local doc = readerui.document.file
        local BackgroundJobs = require("background_jobs")
        BackgroundJobs.clearKeys()
        local inserted_jobs = {}
        local orig_insert = BackgroundJobs.insert
        BackgroundJobs.insert = function(job)
          table.insert(inserted_jobs, job)
        end
        local orig_ui = plugin_instance.ui

        finally(function()
          BackgroundJobs.insert = orig_insert
          plugin_instance.ui = orig_ui
          BackgroundJobs.clearKeys()
        end)

        sync_manager:addToChangedDocumentsFile(doc)

        plugin_instance.ui = { document = { file = doc } }
        sync_manager:_dispatchNextSync()

        plugin_instance.ui = nil
        sync_manager:_dispatchNextSync()

        assert.is_equal(1, #inserted_jobs)
      end
    )

    it(
      "returns boolean indicating dispatch status and manages running state",
      function()
        local doc = readerui.document.file
        local NetworkMgr = require("ui/network/manager")
        local old_isOnline = NetworkMgr.isOnline
        NetworkMgr.isOnline = function()
          return true
        end

        finally(function()
          NetworkMgr.isOnline = old_isOnline
          sync_manager.running = nil
          plugin_instance.settings.network_auto_sync = true
          os.remove(sync_manager:changedDocumentsFile())
        end)

        -- 1. A sync is already running (running set) -> returns false
        sync_manager.running = true
        assert.is_false(sync_manager:_dispatchNextSync())
        sync_manager.running = nil

        -- 2. network_auto_sync is off and the queue has a book -> returns false, running stays nil
        plugin_instance.settings.network_auto_sync = false
        sync_manager:_writeChangedDocumentsFile({ doc })
        assert.is_false(sync_manager:_dispatchNextSync())
        assert.is_nil(sync_manager.running)

        -- 3. auto sync is on and the queue is empty -> returns false
        plugin_instance.settings.network_auto_sync = true
        os.remove(sync_manager:changedDocumentsFile())
        assert.is_false(sync_manager:_dispatchNextSync())
        assert.is_nil(sync_manager.running)

        -- 4. auto sync is on, a book is queued, nothing is running -> returns true, running is set
        sync_manager:_writeChangedDocumentsFile({ doc })
        assert.is_true(sync_manager:_dispatchNextSync())
        assert.is_true(sync_manager.running)
      end
    )

    it(
      "dispatches background sync sequentially for multiple changed documents",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc2.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:addToChangedDocumentsFile(doc1)
        sync_manager:addToChangedDocumentsFile(doc2)

        -- Only 1 job is in flight initially
        assert.is_equal(initial_count + 1, #jobs)

        -- Completing the first job with success dispatches the next queued document
        local job1 = jobs[#jobs]
        local tmp_json = DataStorage:getTmpDir() .. "/test_seq1.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        job1.result = { file = doc1, json_path = tmp_json, success = true }
        job1.callback(job1)

        assert.is_equal(initial_count + 2, #jobs)
      end
    )

    it(
      "pauses queue and moves document to back when child job fails",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_fail.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)
        local dispatched = track_dispatched_file()

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        local track_path = sync_manager:changedDocumentsFile()
        util.writeToFile(dump({ doc1, doc2 }), track_path, true)

        sync_manager:_dispatchNextSync()

        -- Job 1 (doc1) is forked
        assert.is_equal(initial_count + 1, #jobs)
        local job1 = jobs[#jobs]

        -- Job 1 fails
        job1.result = { file = doc1, success = false }
        job1.callback(job1)

        -- Queue paused: job 2 is NOT forked immediately
        assert.is_equal(initial_count + 1, #jobs)

        -- doc1 was moved to back: pending list is {doc2, doc1}
        local total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(2, total)
        assert.are.same({ doc2, doc1 }, pending)

        -- On next trigger, doc2 is dispatched because it is now at the front
        sync_manager:_dispatchNextSync()
        assert.is_equal(initial_count + 2, #jobs)
        assert.is_equal(doc2, dispatched.file)
      end
    )

    it(
      "pauses queue and moves document to back when child job crashes with invalid result",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_crash.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)
        local dispatched = track_dispatched_file()

        for _, invalid_res in ipairs({ false, 222, 255 }) do
          os.remove(sync_manager:changedDocumentsFile())
          require("background_jobs").clearKeys()
          local jobs = require("pluginshare").backgroundJobs
          for k in pairs(jobs) do
            jobs[k] = nil
          end
          sync_manager.running = nil

          local track_path = sync_manager:changedDocumentsFile()
          util.writeToFile(dump({ doc1, doc2 }), track_path, true)

          local count_before = #jobs

          sync_manager:_dispatchNextSync()
          assert.is_equal(count_before + 1, #jobs)

          -- Child crashed: CommandRunner returns false, 222, or 255 (timeout)
          local job1 = jobs[#jobs]
          job1.result = invalid_res
          job1.callback(job1)

          -- Crashed book remains pending and moved to back: {doc2, doc1}
          local total, pending = sync_manager:getPendingChangedDocuments()
          assert.is_equal(2, total)
          assert.are.same({ doc2, doc1 }, pending)

          -- Queue paused: next queued document was NOT dispatched immediately
          assert.is_equal(count_before + 1, #jobs)

          -- On next trigger, doc2 dispatches
          sync_manager:_dispatchNextSync()
          assert.is_equal(count_before + 2, #jobs)
          assert.is_equal(doc2, dispatched.file)
        end
      end
    )

    it(
      "dispatches pending documents in queue order (FIFO)",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_fifo.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)
        local dispatched = track_dispatched_file()

        local track_path = sync_manager:changedDocumentsFile()
        util.writeToFile(dump({ doc2, doc1 }), track_path, true)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:_dispatchNextSync()

        assert.is_equal(initial_count + 1, #jobs)
        assert.is_equal(doc2, dispatched.file)
      end
    )

    it(
      "loads legacy map format into an array and appends newly added documents to the back",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_legacy2.epub"
        local doc3 = test_data_dir .. "/doc_legacy3.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc3)
        finally(function()
          os.remove(doc2)
          os.remove(doc3)
        end)

        local track_path = sync_manager:changedDocumentsFile()
        util.writeToFile(
          dump({
            [doc1] = true,
            [doc2] = true,
          }),
          track_path,
          true
        )

        local total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(2, total)
        assert.truthy(util.arrayContains(pending, doc1))
        assert.truthy(util.arrayContains(pending, doc2))

        -- Adding doc3 appends it as the third item in the array
        plugin_instance.settings.network_auto_sync = false
        sync_manager:addToChangedDocumentsFile(doc3)
        plugin_instance.settings.network_auto_sync = true

        total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(3, total)
        assert.is_equal(doc3, pending[3])

        -- Verify the written file on disk is an array
        local on_disk = dofile(track_path)
        assert.is_not_nil(on_disk[1])
        assert.is_equal(doc3, on_disk[3])
      end
    )

    it(
      "re-adding an existing pending document preserves its queued position",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_keep_pos.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)

        local track_path = sync_manager:changedDocumentsFile()
        util.writeToFile(dump({ doc1, doc2 }), track_path, true)

        -- Re-add doc1
        sync_manager:addToChangedDocumentsFile(doc1)

        local total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(2, total)
        assert.are.same({ doc1, doc2 }, pending)
      end
    )

    it(
      "failure does not re-add a document that was removed from pending during the job",
      function()
        local doc1 = readerui.document.file
        sync_manager:addToChangedDocumentsFile(doc1)

        local jobs = require("pluginshare").backgroundJobs
        local job1 = jobs[#jobs]

        -- Document was removed (e.g. by manual sync or deletion) while job ran
        sync_manager:removeFromChangedDocumentsFileByPath(doc1)

        -- Job finishes with failure
        job1.result = { file = doc1, success = false }
        job1.callback(job1)

        local total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
        assert.falsy(util.arrayContains(pending, doc1))
      end
    )

    it(
      "document edited during sync remains pending, moves to back, and next document dispatches",
      function()
        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_mid_edit.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          os.remove(doc2)
        end)
        local dispatched = track_dispatched_file()

        local track_path = sync_manager:changedDocumentsFile()
        util.writeToFile(dump({ doc1, doc2 }), track_path, true)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_manager:_dispatchNextSync()
        assert.is_equal(initial_count + 1, #jobs)
        assert.is_equal(doc1, dispatched.file)
        local job1 = jobs[#jobs]

        -- During job, user adds an annotation so local_list ~= base_list
        local new_ann = { text = "Edited mid sync", page = 1 }
        table.insert(readerui.annotation.annotations, new_ann)

        local tmp_json = DataStorage:getTmpDir() .. "/test_mid_edit.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        job1.result = { file = doc1, json_path = tmp_json, success = true }
        job1.callback(job1)

        -- doc1 remains pending and moved to back: {doc2, doc1}
        local total, pending = sync_manager:getPendingChangedDocuments()
        assert.is_equal(2, total)
        assert.are.same({ doc2, doc1 }, pending)

        -- Next document (doc2) was dispatched immediately
        assert.is_equal(initial_count + 2, #jobs)
        assert.is_equal(doc2, dispatched.file)
      end
    )

    it(
      "child process loops queryOnlineState and sleeps until online before writing JSON and snapshot",
      function()
        local doc = readerui.document.file
        sync_manager:addToChangedDocumentsFile(doc)

        local jobs = require("pluginshare").backgroundJobs
        local job = jobs[#jobs]

        local NetworkMgr = require("ui/network/manager")
        local old_isOnline = NetworkMgr.isOnline
        local old_query = NetworkMgr.queryOnlineState
        local ffi_util = require("ffi/util")
        local old_sleep = ffi_util.sleep

        local online_checks = 0
        local query_calls = 0
        local sleep_calls = {}
        local json_written_while_offline = false

        NetworkMgr.isOnline = function()
          online_checks = online_checks + 1
          return online_checks >= 3
        end

        NetworkMgr.queryOnlineState = function()
          query_calls = query_calls + 1
        end

        ffi_util.sleep = function(sec)
          table.insert(sleep_calls, sec)
        end

        local old_writeJSON = sync_manager._writeAnnotationsJSON
        sync_manager._writeAnnotationsJSON = function(self_m, d)
          if not NetworkMgr:isOnline() then
            json_written_while_offline = true
          end
          return old_writeJSON(self_m, d)
        end

        finally(function()
          NetworkMgr.isOnline = old_isOnline
          NetworkMgr.queryOnlineState = old_query
          ffi_util.sleep = old_sleep
          sync_manager._writeAnnotationsJSON = old_writeJSON
        end)

        local action_res = job.action()
        assert.is_table(action_res)
        assert.is_true(action_res.success)
        assert.is_false(json_written_while_offline)
        assert.is_true(query_calls >= 1)
        assert.is_true(#sleep_calls >= 1)
        assert.is_equal(10, sleep_calls[1])
      end
    )

    it(
      "child process queries online state before checking isOnline to avoid stale cached online state",
      function()
        local doc = readerui.document.file
        sync_manager:addToChangedDocumentsFile(doc)

        local jobs = require("pluginshare").backgroundJobs
        local job = jobs[#jobs]

        local NetworkMgr = require("ui/network/manager")
        local old_isOnline = NetworkMgr.isOnline
        local old_query = NetworkMgr.queryOnlineState
        local ffi_util = require("ffi/util")
        local old_sleep = ffi_util.sleep

        local online = true
        local query_calls = 0
        local sleep_calls = {}
        local json_written_queries = nil
        local json_written_online = nil

        NetworkMgr.isOnline = function()
          return online
        end

        NetworkMgr.queryOnlineState = function()
          query_calls = query_calls + 1
          if query_calls == 1 then
            online = false
          elseif query_calls == 2 then
            online = true
          end
        end

        ffi_util.sleep = function(sec)
          table.insert(sleep_calls, sec)
          if #sleep_calls > 5 then
            error("Loop exceeded max sleep calls")
          end
        end

        local old_writeJSON = sync_manager._writeAnnotationsJSON
        sync_manager._writeAnnotationsJSON = function(self_m, d)
          json_written_queries = query_calls
          json_written_online = online
          return old_writeJSON(self_m, d)
        end

        finally(function()
          NetworkMgr.isOnline = old_isOnline
          NetworkMgr.queryOnlineState = old_query
          ffi_util.sleep = old_sleep
          sync_manager._writeAnnotationsJSON = old_writeJSON
        end)

        local action_res = job.action()
        assert.is_table(action_res)
        assert.is_true(action_res.success)
        assert.is_equal(2, json_written_queries)
        assert.is_true(json_written_online)
        assert.is_equal(1, #sleep_calls)
        assert.is_equal(10, sleep_calls[1])
      end
    )

    it(
      "turning network_auto_sync off does not cancel an in-flight background job",
      function()
        local doc = readerui.document.file
        sync_manager:addToChangedDocumentsFile(doc)

        local jobs = require("pluginshare").backgroundJobs
        local job = jobs[#jobs]

        assert.is_true(sync_manager.running)

        plugin_instance.settings.network_auto_sync = false

        local tmp_json = DataStorage:getTmpDir() .. "/test_turn_off.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        job.result = { file = doc, json_path = tmp_json, success = true }
        job.callback(job)

        assert.is_nil(sync_manager.running)
      end
    )

    it(
      "waits for network connectivity between queued background sync jobs",
      function()
        local NetworkMgr = require("ui/network/manager")
        local NetworkListener = require("ui/network/networklistener")
        local old_isOnline = NetworkMgr.isOnline

        local doc1 = readerui.document.file
        local doc2 = test_data_dir .. "/doc_net_drop.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          NetworkMgr.isOnline = old_isOnline
          os.remove(doc2)
        end)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        NetworkMgr.isOnline = function()
          return true
        end

        sync_manager:addToChangedDocumentsFile(doc1)
        sync_manager:addToChangedDocumentsFile(doc2)

        -- Job 1 is forked
        assert.is_equal(initial_count + 1, #jobs)
        local job1 = jobs[#jobs]

        -- Network drops while job 1 is in flight
        NetworkMgr.isOnline = function()
          return false
        end

        -- Finish job 1 callback as success, which attempts to dispatch next document (doc2)
        local tmp_json = DataStorage:getTmpDir() .. "/test_net_drop.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        job1.result = { file = doc1, json_path = tmp_json, success = true }
        job1.callback(job1)

        -- Next queued job must NOT be forked while offline, held in NetworkListener
        assert.is_equal(initial_count + 1, #jobs)
        assert.is_equal("0 / 1", NetworkListener:countsOfPendingJobs())

        -- Network comes back online
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkListener:onNetworkOnline()
        fastforward_ui_events()

        -- The next queued document is now forked
        assert.is_equal(initial_count + 2, #jobs)
        local job2 = jobs[#jobs]
        job2.result = { success = false }
        job2.callback(job2)
      end
    )

    it(
      "prunes deleted book and dispatches next queued document after waiting for network",
      function()
        local NetworkMgr = require("ui/network/manager")
        local NetworkListener = require("ui/network/networklistener")
        local old_isOnline = NetworkMgr.isOnline

        local doc1 = test_data_dir .. "/doc_del_wait.epub"
        local doc2 = test_data_dir .. "/doc_next_after_del.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc1)
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        finally(function()
          NetworkMgr.isOnline = old_isOnline
          os.remove(doc1)
          os.remove(doc2)
        end)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        -- Network is offline when sync is initiated
        NetworkMgr.isOnline = function()
          return false
        end

        sync_manager:addToChangedDocumentsFile(doc1)
        sync_manager:addToChangedDocumentsFile(doc2)

        -- Nothing forked directly while offline, doc1 is held waiting for network
        assert.is_equal(initial_count, #jobs)
        assert.is_equal("0 / 1", NetworkListener:countsOfPendingJobs())

        -- While doc1 waits for network, doc1 file is deleted from disk
        os.remove(doc1)

        -- Network comes back online
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkListener:onNetworkOnline()
        fastforward_ui_events()

        -- doc1 was pruned from pending documents without forking
        local _, pending = sync_manager:getPendingChangedDocuments()
        assert.falsy(util.arrayContains(pending, doc1))
        assert.truthy(util.arrayContains(pending, doc2))

        -- Next document (doc2) is forked
        assert.is_equal(initial_count + 1, #jobs)

        local job2 = jobs[#jobs]
        job2.result = { file = doc2, success = false }
        job2.callback(job2)
      end
    )

    it(
      "dispatches next queued document when held-back book is removed from sync queue while waiting for network",
      function()
        local NetworkMgr = require("ui/network/manager")
        local NetworkListener = require("ui/network/networklistener")
        local old_isOnline = NetworkMgr.isOnline

        local doc1 = test_data_dir .. "/doc_rem_wait.epub"
        local doc2 = test_data_dir .. "/doc_next_after_rem.epub"
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc1)
        require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)
        local get_dispatched = track_dispatched_file()
        finally(function()
          NetworkMgr.isOnline = old_isOnline
          os.remove(doc1)
          os.remove(doc2)
        end)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        -- Network is offline when sync is initiated
        NetworkMgr.isOnline = function()
          return false
        end

        sync_manager:addToChangedDocumentsFile(doc1)
        sync_manager:addToChangedDocumentsFile(doc2)

        -- Nothing forked directly while offline, doc1 is held waiting for network
        assert.is_equal(initial_count, #jobs)
        assert.is_equal("0 / 1", NetworkListener:countsOfPendingJobs())

        -- While doc1 waits for network, doc1 is removed from queue but stays on disk
        sync_manager:removeFromChangedDocumentsFileByPath(doc1)
        assert.truthy(util.fileExists(doc1))

        -- Network comes back online
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkListener:onNetworkOnline()
        fastforward_ui_events()

        -- Exactly one new fork job: doc1 was never forked, doc2 was dispatched and forked
        assert.is_equal(initial_count + 1, #jobs)
        assert.is_equal(doc2, get_dispatched())

        local _, pending = sync_manager:getPendingChangedDocuments()
        assert.are.same({ doc2 }, pending)

        local job2 = jobs[#jobs]
        job2.result = { file = doc2, success = false }
        job2.callback(job2)
      end
    )

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

  describe("remote.sync_annotations finish_cb contract", function()
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
        assert.is_false(util.fileExists(dummy_json .. ".sync"))
        assert.is_false(util.fileExists(dummy_json))
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
        assert.is_false(util.fileExists(dummy_json))
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
        assert.is_false(util.fileExists(dummy_json .. ".sync"))
        assert.is_false(util.fileExists(dummy_json))
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

        assert.is_false(util.fileExists(dummy_json))
        assert.is_false(util.fileExists(tmp_temp))
        assert.is_false(util.fileExists(tmp_sync))
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
      "skips remote sync and cleans tmp when network is connected but not online",
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
        assert.is_false(util.fileExists(dummy_json))
      end
    )
  end)

  describe("End-to-end background 3-way merge integration", function()
    local BackgroundJobs, ffiutil, DocSettings, NetworkMgr
    local remote_store = {}
    local old_insertKeyed, old_sync, old_server, old_isOnline

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
      return not not (docs and util.arrayContains(docs, file))
    end

    local function encode(list)
      return json.encode(list)
    end

    local function copy(t)
      return util.tableDeepCopy(t)
    end

    local last_child_res
    local function fork_like(during, skip_callback)
      local in_job = false
      BackgroundJobs.insertKeyed = function(job)
        if in_job then
          return true
        end
        in_job = true
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
        in_job = false
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
      last_child_res = nil
      NetworkMgr = require("ui/network/manager")
      old_isOnline = NetworkMgr.isOnline
      NetworkMgr.isOnline = function()
        return true
      end

      BackgroundJobs = require("background_jobs")
      old_insertKeyed = BackgroundJobs.insertKeyed
      ffiutil = require("ffi/util")
      DocSettings = require("frontend/docsettings")

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
        local L = mk(1, "L_local", "2026-01-01 10:00:00")
        local R = mk(2, "R_remote", "2026-01-02 10:00:00")

        local ds = DocSettings:open(doc)
        ds:save("annotations", { L })
        ds:flush()
        remote_store[name] = encode({ R })

        fork_like()
        sync_manager:addToChangedDocumentsFile(doc)

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

        local remote_after = json.decode(remote_store[name])
        assert.are.equal(3, #remote_after)
        for _, item in ipairs(remote_after) do
          assert.is_nil(item.deleted)
        end
      end
    )

    it(
      "preserves restored annotations during background sync of inactive document",
      function()
        local doc, name = new_doc("restore_inactive_doc")
        local function mk(n, text, ts, deleted, ts_updated)
          local p0 = "/body/DocFragment[3]/body/p[" .. n .. "]/text().0"
          return {
            page = p0,
            pos0 = p0,
            pos1 = (p0:gsub("%.0$", ".20")),
            text = text,
            datetime = ts,
            datetime_updated = ts_updated or ts,
            deleted = deleted,
            drawer = "lighten",
          }
        end

        local H = mk(1, "H_keep", "2026-01-01 10:00:00")
        local A_tomb =
          mk(2, "A_restored", "2026-01-01 10:00:00", true, "2026-01-02 10:00:00")
        local B_tomb =
          mk(3, "B_restored", "2026-01-01 10:00:00", true, "2026-01-02 10:00:00")

        local A_restored =
          mk(2, "A_restored", "2026-01-01 10:00:00", false, "2026-01-03 10:00:00")
        local B_restored =
          mk(3, "B_restored", "2026-01-01 10:00:00", false, "2026-01-03 10:00:00")

        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()

        util.writeToFile(
          encode({ A_tomb, B_tomb, H }),
          sync_manager:getSyncCachePath(doc)
        )
        remote_store[name] = encode({ A_restored, B_restored, H })

        fork_like()
        sync_manager:addToChangedDocumentsFile(doc)

        -- Sidecar must contain A, B, and H with no deleted == true
        local side = DocSettings:open(doc):readTable("annotations")
        assert.are.equal(3, #side)
        local side_texts = {}
        for _, item in ipairs(side) do
          table.insert(side_texts, item.text)
          assert.are_not.equal(true, item.deleted)
        end
        table.sort(side_texts)
        assert.are.same({ "A_restored", "B_restored", "H_keep" }, side_texts)

        -- Remote must contain A, B, and H with no deleted == true
        local remote = json.decode(remote_store[name])
        assert.are.equal(3, #remote)
        local remote_texts = {}
        for _, item in ipairs(remote) do
          table.insert(remote_texts, item.text)
          assert.are_not.equal(true, item.deleted)
        end
        table.sort(remote_texts)
        assert.are.same({ "A_restored", "B_restored", "H_keep" }, remote_texts)

        -- .sync cache must contain A, B, and H with no deleted == true
        local cache = utils.read_json(sync_manager:getSyncCachePath(doc))
        assert.are.equal(3, #cache)
        local cache_texts = {}
        for _, item in ipairs(cache) do
          table.insert(cache_texts, item.text)
          assert.are_not.equal(true, item.deleted)
        end
        table.sort(cache_texts)
        assert.are.same({ "A_restored", "B_restored", "H_keep" }, cache_texts)
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

        sync_manager:addToChangedDocumentsFile(file)

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

        -- Callback is lost / skipped (simulating child finished but parent died/dropped)
        fork_like(nil, true)
        sync_manager:addToChangedDocumentsFile(doc)

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

        fork_like(function()
          local H = hl(doc, 19, "H_during_noop")
          readerui.annotation:addItem(H)
          plugin_instance:onAnnotationsModified({ H })
        end)

        sync_manager:addToChangedDocumentsFile(file)

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

        fork_like(function()
          plugin_instance:init()
          local H = hl(doc, 25, "H_added_during_job")
          readerui.annotation:addItem(H)
          plugin_instance:onAnnotationsModified({ H })
        end)

        sync_manager:addToChangedDocumentsFile(file)

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

        NetworkMgr.isOnline = function()
          return false
        end

        sync_manager:addToChangedDocumentsFile(file)
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

        fork_like()
        sync_manager:addToChangedDocumentsFile(file)

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
        local L = mk(1, "L_del", "2026-01-01 10:00:00")
        local R = mk(2, "R_del", "2026-01-02 10:00:00")

        local ds = DocSettings:open(doc)
        ds:save("annotations", { L })
        ds:flush()
        remote_store[name] = encode({ L, R })

        local lfs = require("libs/libkoreader-lfs")
        local sdr_dir = DocSettings:getSidecarDir(doc)

        fork_like(function()
          -- Simulate user deleting book and its sidecar directory while child runs
          os.remove(doc)
          os.execute("rm -rf " .. sdr_dir)
        end)

        sync_manager:addToChangedDocumentsFile(doc)

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

        local during_snapshot_exists = false
        local during_uploaded_exists = false
        fork_like(function()
          if last_child_res and last_child_res.json_path then
            during_snapshot_exists = util.fileExists(last_child_res.json_path .. ".snapshot")
            during_uploaded_exists = util.fileExists(last_child_res.json_path .. ".uploaded")
          end
        end)

        sync_manager:addToChangedDocumentsFile(doc)

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

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:addToChangedDocumentsFile(doc)

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )

    it(
      "cleans all child tmp files after callback when sync has nothing to upload",
      function()
        local doc, name = new_doc("cleanup_noop")

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:addToChangedDocumentsFile(doc)

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

        SyncService.sync = function(server, path, sync_cb, is_silent, finish_cb)
          if finish_cb then
            finish_cb(false)
          end
        end

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
        end)
        sync_manager:addToChangedDocumentsFile(doc)

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

        local json_path
        fork_like(function()
          json_path = last_child_res.json_path
          os.remove(doc)
          local sdr_dir = DocSettings:getSidecarDir(doc)
          os.execute("rm -rf " .. sdr_dir)
        end)
        sync_manager:addToChangedDocumentsFile(doc)

        assert.is_string(json_path)
        assert.is_false(util.fileExists(json_path .. ".snapshot"))
        assert.is_false(util.fileExists(json_path .. ".uploaded"))
      end
    )

    it(
      "logs the error when the background sync throws",
      function()
        local doc, name = new_doc("sync_throws")
        local H = mk(1, "H_throws")
        local ds = DocSettings:open(doc)
        ds:save("annotations", { H })
        ds:flush()

        local logger = require("logger")
        local old_err = logger.err
        local logged_errors = {}
        logger.err = function(...)
          local args = { ... }
          local parts = {}
          for i = 1, select("#", ...) do
            table.insert(parts, tostring(args[i]))
          end
          table.insert(logged_errors, table.concat(parts, " "))
        end
        finally(function()
          logger.err = old_err
        end)

        SyncService.sync = function()
          error("simulated sync failure")
        end

        fork_like()
        sync_manager:addToChangedDocumentsFile(doc)

        assert.is_table(last_child_res)
        assert.is_false(last_child_res.success)

        local found_log = false
        for _, err_msg in ipairs(logged_errors) do
          if err_msg:find(doc, 1, true) and err_msg:find("simulated sync failure", 1, true) then
            found_log = true
            break
          end
        end
        assert.is_true(found_log)
        assert.is_true(is_pending(doc))
      end
    )

    it(
      "re-forks background sync after callback when book is edited during an in-flight job",
      function()
        local file, name = new_doc("doc_retrigger_edited")
        local old_file = readerui.document.file
        finally(function()
          readerui.document.file = old_file
          os.remove(file)
        end)

        local K = mk(1, "K_keep", "2026-01-01 10:00:00")
        util.writeToFile(encode({ K }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ K })
        readerui.document.file = file
        readerui.annotation.annotations = copy({ K })

        local jobs_dispatched = 0
        local during_triggered = false
        local first_callback_started = false
        local second_job_dispatched_after_first_callback = false

        BackgroundJobs.insertKeyed = function(job)
          jobs_dispatched = jobs_dispatched + 1
          if jobs_dispatched == 2 then
            second_job_dispatched_after_first_callback = first_callback_started
          end
          local res = false
          local ok, ret = pcall(job.action)
          if ok then
            res = ret
          end
          last_child_res = res
          if not during_triggered then
            during_triggered = true
            local H = mk(2, "H_during", "2026-01-01 12:00:00")
            readerui.annotation:addItem(H)
            plugin_instance:onAnnotationsModified({ H })
            assert.is_equal(1, jobs_dispatched)
          end
          first_callback_started = true
          job.result = res
          job.callback(job)
          return true
        end

        sync_manager:addToChangedDocumentsFile(file)

        assert.is_equal(2, jobs_dispatched)
        assert.is_true(second_job_dispatched_after_first_callback)
        assert.is_false(is_pending(file))
      end
    )

    it(
      "does not re-fork background sync if book was not edited during an in-flight job",
      function()
        local file, name = new_doc("doc_retrigger_not_edited")
        local old_file = readerui.document.file
        finally(function()
          readerui.document.file = old_file
          os.remove(file)
        end)

        local K = mk(1, "K_keep", "2026-01-01 10:00:00")
        util.writeToFile(encode({ K }), sync_manager:getSyncCachePath(file))
        remote_store[name] = encode({ K })
        readerui.document.file = file
        readerui.annotation.annotations = copy({ K })

        local jobs_dispatched = 0
        local during_triggered = false

        BackgroundJobs.insertKeyed = function(job)
          jobs_dispatched = jobs_dispatched + 1
          local res = false
          local ok, ret = pcall(job.action)
          if ok then
            res = ret
          end
          last_child_res = res
          if not during_triggered then
            during_triggered = true
          end
          job.result = res
          job.callback(job)
          return true
        end

        sync_manager:addToChangedDocumentsFile(file)

        assert.is_equal(1, jobs_dispatched)
        assert.is_false(is_pending(file))
      end
    )
  end)
end)
