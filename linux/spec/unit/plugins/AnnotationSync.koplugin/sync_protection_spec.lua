describe("AnnotationSync Sync Protection & Regressions", function()
  local ReaderUI, UIManager, Geom, SyncService
  local AnnotationSyncPlugin, highlight_db, test_utils, json
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_protection_tmp"
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

    highlight_db = require("plugins/AnnotationSync.koplugin/highlight_db")
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
    readerui.annotation.annotations = {}
    os.remove(sync_instance.manager:changedDocumentsFile())
    test_utils.mock_sync_service(SyncService)
  end)

  it(
    "should preserve annotations during bulk sync even if export file is missing (Issue 23)",
    function()
      -- 1. Create a highlight
      UIManager:show(readerui)
      readerui.rolling:onGotoPage(3)
      fastforward_ui_events()

      test_utils.emulate_highlight(readerui, highlight_db[1])
      assert.is_equal(1, #readerui.annotation.annotations)

      -- 2. Mark as dirty
      sync_instance.manager:addToChangedDocumentsFile(readerui.document.file)

      -- 3. Mock sync to check what's being sent
      local last_uploaded_data
      local old_sync = SyncService.sync
      SyncService.sync = function(server, local_path, callback, upload_only)
        local result = callback(local_path, local_path, local_path)
        local f = io.open(local_path, "r")
        last_uploaded_data = json.decode(f:read("*all"))
        f:close()
        return result
      end

      G_reader_settings:save("cloud_download_dir", "mock")
      G_reader_settings:save(
        "cloud_server_object",
        json.encode({ url = "mock" })
      )

      -- 4. Trigger Sync All
      sync_instance.manager:syncAllChangedDocuments()

      -- 5. Verify the 1 highlight was found and included in the sync data
      local count = 0
      if last_uploaded_data then
        for _ in pairs(last_uploaded_data) do
          count = count + 1
        end
      end
      assert.is_equal(1, count)

      SyncService.sync = old_sync
    end
  )

  it(
    "should read annotations from DocSettings directly (Regression Issue 23)",
    function()
      local mock_ds = {
        open = function(this, file)
          return {
            readTable = function(self_ds, key)
              if key == "annotations" then
                return { { page = "test_page", pos0 = "p0", pos1 = "p1" } }
              end
            end,
            readTableRef = function(self_ds, key)
              if key == "annotations" then
                return { { page = "test_page", pos0 = "p0", pos1 = "p1" } }
              end
              return {}
            end,
          }
        end,
      }

      -- 1. Mock the dependency
      local old_ds_module = package.loaded["frontend/docsettings"]
      package.loaded["frontend/docsettings"] = mock_ds

      -- 2. Load Manager directly (bypassing Plugin/Main)
      -- We must force a reload of manager to pick up the new docsettings mock
      local old_manager =
        package.loaded["plugins/AnnotationSync.koplugin/manager"]
      package.loaded["plugins/AnnotationSync.koplugin/manager"] = nil
      local SyncManager = require("plugins/AnnotationSync.koplugin/manager")

      -- 3. Instantiate Manager with a dummy plugin interface
      local mock_plugin = { ui = readerui, settings = {} }
      local manager_instance = SyncManager:new(mock_plugin)

      -- 4. Verify
      local result =
        manager_instance:getAnnotationsForDocument({ file = "any.epub" })
      assert.is_equal(1, #result)
      assert.is_equal("test_page", result[1].page)

      -- 5. Cleanup
      package.loaded["frontend/docsettings"] = old_ds_module
      package.loaded["plugins/AnnotationSync.koplugin/manager"] = old_manager
    end
  )

  it(
    "should skip deletions if local map is empty but last sync was not (Issue 23 Protection)",
    function()
      local annotations_mod =
        require("plugins/AnnotationSync.koplugin/annotations")
      local local_file =
        test_utils.write_mock_json(test_data_dir, "prot_local.json", {})
      local last_sync_file =
        test_utils.write_mock_json(test_data_dir, "prot_last.json", {
          ["p1||p2"] = { pos0 = "p1", pos1 = "p2", page = 1, text = "Gone?" },
        })
      local income_file =
        test_utils.write_mock_json(test_data_dir, "prot_income.json", {
          ["p1||p2"] = { pos0 = "p1", pos1 = "p2", page = 1, text = "Gone?" },
        })

      local ok, active = annotations_mod.sync_callback(
        readerui.document,
        local_file,
        last_sync_file,
        income_file,
        false
      )

      assert.is_true(ok)
      -- Issue 23 Protection: remote annotation is preserved, NOT deleted
      assert.is_equal(1, #active)
      assert.is_equal("Gone?", active[1].text)

      local f = io.open(local_file, "r")
      local disk_map = json.decode(f:read("*a"))
      f:close()
      assert.is_not_nil(disk_map["p1||p2"])
      assert.falsy(disk_map["p1||p2"].deleted)
    end
  )

  it(
    "should allow deletions if local map is empty but 'force' is true (Manual Override)",
    function()
      local annotations_mod =
        require("plugins/AnnotationSync.koplugin/annotations")
      local local_file =
        test_utils.write_mock_json(test_data_dir, "prot_local_force.json", {})
      local last_sync_file =
        test_utils.write_mock_json(test_data_dir, "prot_last_force.json", {
          ["p1||p2"] = { pos0 = "p1", pos1 = "p2", page = 1, text = "Gone?" },
        })
      local income_file =
        test_utils.write_mock_json(test_data_dir, "prot_income_force.json", {
          ["p1||p2"] = { pos0 = "p1", pos1 = "p2", page = 1, text = "Gone?" },
        })

      local ok, active = annotations_mod.sync_callback(
        readerui.document,
        local_file,
        last_sync_file,
        income_file,
        true
      )

      assert.is_true(ok)
      -- Manual override allows deletion propagation
      assert.is_equal(0, #active)

      local f = io.open(local_file, "r")
      local disk_map = json.decode(f:read("*a"))
      f:close()
      assert.is_not_nil(disk_map["p1||p2"])
      assert.is_true(disk_map["p1||p2"].deleted)
    end
  )

  it(
    "should STILL propagate deletions if local list is NOT completely empty",
    function()
      local remote_ann = {
        ["p1||p1"] = {
          page = 1,
          pos0 = "p1",
          pos1 = "p1",
          text = "Remote 1",
          datetime_updated = "2026-01-01 00:00:00",
        },
        ["p2||p2"] = {
          page = 2,
          pos0 = "p2",
          pos1 = "p2",
          text = "Remote 2",
          datetime_updated = "2026-01-01 00:00:00",
        },
      }

      local old_sync = SyncService.sync
      SyncService.sync = function(
        server,
        local_path,
        callback,
        upload_only,
        custom_cached_path
      )
        local cached_path = test_data_dir .. "/cached_partial.json"
        local income_path = test_data_dir .. "/income_partial.json"

        local f = io.open(cached_path, "w")
        f:write(json.encode(remote_ann))
        f:close()

        f = io.open(income_path, "w")
        f:write(json.encode(remote_ann))
        f:close()

        local result = callback(local_path, cached_path, income_path)
        if result then
          local ffiutil = require("ffi/util")
          local cached_dest = custom_cached_path or (local_path .. ".sync")
          ffiutil.copyFile(local_path, cached_dest)
        end
        return result
      end

      G_reader_settings:save("cloud_download_dir", "mock")
      G_reader_settings:save(
        "cloud_server_object",
        json.encode({ url = "mock" })
      )

      readerui.annotation.annotations = {
        {
          page = 1,
          pos0 = "p1",
          pos1 = "p1",
          text = "Remote 1",
          datetime_updated = "2026-01-01 00:00:00",
        },
      }

      sync_instance.manager:syncDocument(readerui.document, false)

      local cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)

      local f = io.open(cached_path, "r")
      local saved_data = json.decode(f:read("*all"))
      f:close()

      assert.is_not_nil(saved_data["p2||p2"])
      assert.is_true(saved_data["p2||p2"].deleted)

      SyncService.sync = old_sync
    end
  )

  it("should protect PDF annotations similarly (geometry keys)", function()
    local remote_ann = {
      ["1|10|10||20|20"] = {
        page = 1,
        pos0 = { x = 10, y = 10 },
        pos1 = { x = 20, y = 20 },
        text = "PDF Note",
        datetime_updated = "2026-01-01 00:00:00",
      },
    }

    local old_sync = SyncService.sync
    SyncService.sync = function(
      server,
      local_path,
      callback,
      upload_only,
      custom_cached_path
    )
      local cached_path = test_data_dir .. "/cached_pdf.json"
      local income_path = test_data_dir .. "/income_pdf.json"

      local f = io.open(cached_path, "w")
      f:write(json.encode(remote_ann))
      f:close()

      f = io.open(income_path, "w")
      f:write(json.encode(remote_ann))
      f:close()

      local result = callback(local_path, cached_path, income_path)
      if result then
        local ffiutil = require("ffi/util")
        local cached_dest = custom_cached_path or (local_path .. ".sync")
        ffiutil.copyFile(local_path, cached_dest)
      end
      return result
    end

    G_reader_settings:save("cloud_download_dir", "mock")
    G_reader_settings:save("cloud_server_object", json.encode({ url = "mock" }))

    readerui.annotation.annotations = {}

    sync_instance.manager:syncDocument(readerui.document, false)

    assert.is_equal(1, #readerui.annotation.annotations)
    assert.is_equal("PDF Note", readerui.annotation.annotations[1].text)

    SyncService.sync = old_sync
  end)
end)
