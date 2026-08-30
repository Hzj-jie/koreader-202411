describe("AnnotationSync Automation & Settings", function()
  local ReaderUI, UIManager, SyncService, Geom
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_automation_tmp"
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

    highlight_db =
      require("plugins/AnnotationSync.koplugin/highlight_db")
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
    require("background_jobs").clearKeys()
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
      "triggers background incremental fork sync on onTimesChange_1M when network_auto_sync is enabled",
      function()
        sync_instance.settings.network_auto_sync = true
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_jobs_count = #jobs

        local sync_triggered = false
        SyncService.sync = function(server, local_path, callback, upload_only)
          sync_triggered = true
          callback(local_path, local_path, local_path)
        end

        sync_instance:onTimesChange_1M()

        assert.is_equal(initial_jobs_count + 1, #jobs)
        local job = jobs[#jobs]
        assert.is_equal("asap", job.when)
        assert.is_equal("fork", job.executable)
        assert.is_function(job.action)
        assert.is_function(job.callback)

        -- Execute action in child process context
        local action_results = job.action()
        assert.is_true(sync_triggered)
        assert.is_table(action_results)
        assert.is_equal(readerui.document.file, action_results.file)
        assert.is_true(action_results.success)

        -- Execute callback in parent process context
        job.callback({ result = action_results })
        assert.is_false(sync_instance.manager:hasPendingChangedDocuments())
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
      "deduplicates onTimesChange_1M triggers when background sync is active",
      function()
        sync_instance.settings.network_auto_sync = true
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_instance:onTimesChange_1M()
        sync_instance:onTimesChange_1M()

        assert.is_equal(initial_count + 1, #jobs)
      end
    )

    it(
      "prunes missing files in main thread and applies synced annotations in background callback",
      function()
        local jobs = require("pluginshare").backgroundJobs
        local initial_jobs_count = #jobs
        local missing_file = "/path/to/nonexistent/book.epub"
        local active_file = readerui.document.file

        sync_instance.manager:addToChangedDocumentsFile(missing_file)
        sync_instance.manager:addToChangedDocumentsFile(active_file)

        sync_instance.manager:syncPendingDocumentsBg()

        -- Missing file is pruned on main thread immediately
        local _, remaining = sync_instance.manager:getPendingChangedDocuments()
        assert.is_nil(remaining[missing_file])
        assert.is_true(remaining[active_file])

        -- Active file was queued into background jobs
        assert.is_equal(initial_jobs_count + 1, #jobs)
        local job = jobs[#jobs]

        local dummy_merged = { { text = "Sample Annotation", page = 1 } }
        job.callback({
          result = {
            { file = active_file, success = true, merged_list = dummy_merged },
          },
        })

        assert.is_false(sync_instance.manager.is_syncing_pending_bg)
        local total, _ = sync_instance.manager:getPendingChangedDocuments()
        assert.is_equal(0, total)
        assert.is_equal(1, #readerui.annotation.annotations)
        assert.is_equal(
          "Sample Annotation",
          readerui.annotation.annotations[1].text
        )
      end
    )
  end)
end)
