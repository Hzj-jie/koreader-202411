describe("AnnotationSync Automation & Settings", function()
  local UIManager, SyncService
  local AnnotationSyncPlugin, highlight_db, test_utils, json, util
  local readerui, sync_instance
  local DataStorage = require("datastorage")
  local test_data_dir = DataStorage:getDataDir()
    .. "/test_sync_automation_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
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
    local jobs = require("pluginshare").backgroundJobs
    for k in pairs(jobs) do
      jobs[k] = nil
    end
    sync_instance.manager.running = nil
  end)

  after_each(function()
    os.remove(sync_instance.manager:changedDocumentsFile())
    require("background_jobs").clearKeys()
    local jobs = require("pluginshare").backgroundJobs
    for k in pairs(jobs) do
      jobs[k] = nil
    end
    sync_instance.manager.running = nil
  end)

  describe("Settings", function()
    it("respects naming convention settings", function()
      test_utils.emulate_highlight(readerui, highlight_db[1])

      local captured_path
      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        captured_path = local_path
        local res = callback(local_path, local_path, local_path)
        if finish_cb then
          finish_cb(res)
        end
        return res
      end

      finally(test_utils.run_jobs_inline())
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
      "triggers background incremental fork sync on onNetworkOnline when network_auto_sync is enabled",
      function()
        sync_instance.settings.network_auto_sync = false
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)
        sync_instance.settings.network_auto_sync = true

        local jobs = require("pluginshare").backgroundJobs
        local initial_jobs_count = #jobs

        local sync_triggered = false
        SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
          sync_triggered = true
          local res = callback(local_path, local_path, local_path)
          if finish_cb then
            finish_cb(res)
          end
        end

        sync_instance:onNetworkOnline()

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
        assert.is_equal(0, (sync_instance.manager:getPendingChangedDocuments()))
      end
    )

    it("batch processes multiple documents correctly", function()
      local doc1 = readerui.document.file
      local doc2 = test_data_dir .. "/doc2.epub"
      require("ffi/util").copyFile("spec/front/unit/data/juliet.epub", doc2)

      sync_instance.settings.network_auto_sync = false
      sync_instance.manager:addToChangedDocumentsFile(doc1)
      sync_instance.manager:addToChangedDocumentsFile(doc2)

      local synced_files = {}
      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        table.insert(synced_files, local_path)
        local res = callback(local_path, local_path, local_path)
        if finish_cb then
          finish_cb(res)
        end
      end

      finally(test_utils.run_jobs_inline())
      sync_instance.manager:syncAllChangedDocuments()
      fastforward_ui_events()
      assert.is_equal(2, #synced_files)
    end)

    it(
      "ignores onNetworkOnline when network_auto_sync is disabled",
      function()
        sync_instance.settings.network_auto_sync = false
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_jobs_count = #jobs

        sync_instance:onNetworkOnline()

        assert.is_equal(initial_jobs_count, #jobs)
      end
    )

    it(
      "triggers background sync when addToChangedDocumentsFile is called with network_auto_sync enabled",
      function()
        sync_instance.settings.network_auto_sync = true
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        assert.is_equal(initial_count + 1, #jobs)
      end
    )

    it(
      "does not trigger background sync when addToChangedDocumentsFile is called with network_auto_sync disabled",
      function()
        sync_instance.settings.network_auto_sync = false
        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        assert.is_equal(initial_count, #jobs)
        assert.is_true(sync_instance.manager:getPendingChangedDocuments() > 0)
      end
    )

    it(
      "triggers background sync when scanLibraryForUnsyncedDocuments finds new documents",
      function()
        sync_instance.settings.network_auto_sync = true
        local readhistory = require("readhistory")
        local old_hist = readhistory.hist
        readhistory.hist = { { file = readerui.document.file } }
        finally(function()
          readhistory.hist = old_hist
        end)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs

        sync_instance.manager:scanLibraryForUnsyncedDocuments()

        assert.is_equal(initial_count + 1, #jobs)
      end
    )

    it(
      "switching network_auto_sync toggle on triggers background sync",
      function()
        sync_instance.settings.network_auto_sync = false
        sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

        local jobs = require("pluginshare").backgroundJobs
        local initial_count = #jobs
        assert.is_equal(initial_count, #jobs)

        local menu_items = {}
        sync_instance:addToMainMenu(menu_items)
        local settings_table =
          menu_items.annotation_sync_plugin.sub_item_table[1].sub_item_table
        local menu_item
        for _, sub in ipairs(settings_table) do
          if sub.text == "Sync pending books automatically" then
            menu_item = sub
            break
          end
        end
        assert.is_not_nil(menu_item)
        menu_item.callback()

        assert.is_true(sync_instance.settings.network_auto_sync)
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
        -- Earlier tests leave a .sync behind. Without one, the empty book
        -- takes the upload without asking.
        os.remove(sync_instance.manager:getSyncCachePath(active_file))

        sync_instance.manager:addToChangedDocumentsFile(missing_file)
        sync_instance.manager:addToChangedDocumentsFile(active_file)

        -- Missing file is pruned on main thread immediately
        local _, remaining = sync_instance.manager:getPendingChangedDocuments()
        assert.falsy(util.arrayContains(remaining, missing_file))
        assert.truthy(util.arrayContains(remaining, active_file))

        -- Active file was queued into background jobs
        assert.is_equal(initial_jobs_count + 1, #jobs)
        local job = jobs[#jobs]

        local dummy_merged = { { text = "Sample Annotation", page = 1 } }
        local tmp_json = DataStorage:getTmpDir() .. "/test_bg_sync_auto.json"
        util.writeToFile("[]", tmp_json .. ".snapshot")
        util.writeToFile(json.encode(dummy_merged), tmp_json .. ".uploaded")
        job.callback({
          result = {
            file = active_file,
            json_path = tmp_json,
            success = true,
            uploaded = true,
          },
        })

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
