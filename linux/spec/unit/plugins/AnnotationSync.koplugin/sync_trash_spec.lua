describe("AnnotationSync Trash & Restore", function()
  local ReaderUI, UIManager, SyncService, Geom
  local AnnotationSyncPlugin, highlight_db, test_utils, json, annotations_mod
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_trash_tmp"
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
    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")

    highlight_db = require("plugins/AnnotationSync.koplugin/highlight_db")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "mock")
    G_reader_settings:save("cloud_server_object", json.encode({ url = "mock" }))

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

  it(
    "should correctly identify deleted annotations in the sync JSON",
    function()
      -- 1. Setup a sync JSON with one deleted item
      local file = readerui.document.file
      local tmp_dir = require("datastorage"):getTmpDir()

      sync_instance.settings.use_filename = false -- use hash
      local filename = sync_instance.manager:_getAnnotationFilename(file)
      local json_path = tmp_dir .. "/" .. filename

      local mock_data = {
        ["p1||p2"] = { page = 1, pos0 = "p1", pos1 = "p2", text = "Active" },
        ["d1||d2"] = {
          page = 2,
          pos0 = "d1",
          pos1 = "d2",
          text = "Deleted",
          deleted = true,
        },
      }

      local f = io.open(json_path, "w")
      if not f then
        error("Could not open " .. json_path)
      end
      f:write(json.encode(mock_data))
      f:close()

      -- 2. Check getDeletedAnnotations
      local deleted =
        sync_instance.manager:getDeletedAnnotations(readerui.document)
      assert.is_equal(1, #deleted)
      assert.is_equal("Deleted", deleted[1].text)
      assert.is_true(deleted[1].deleted)
    end
  )

  it("should restore a deleted annotation and notify the system", function()
    readerui.annotation.annotations = {
      { page = 1, pos0 = "p1", pos1 = "p2", text = "Existing" },
    }

    local trash_item = {
      page = 2,
      pos0 = "d1",
      pos1 = "d2",
      text = "Restored",
      deleted = true,
      datetime_updated = "old",
    }

    -- Mock event broadcast tracking
    local event_received = false
    local old_event_new = require("ui/event").new
    require("ui/event").new = function(self_ev, name, ...)
      if name == "AnnotationsModified" then
        event_received = true
      end
      return old_event_new(self_ev, name, ...)
    end

    -- 1. Restore
    sync_instance:restoreAnnotation(trash_item)

    -- 2. Verify
    assert.is_false(trash_item.deleted)
    assert.is_not_equal("old", trash_item.datetime_updated)
    assert.is_equal(2, #readerui.annotation.annotations)
    assert.is_true(event_received)

    -- Cleanup
    require("ui/event").new = old_event_new
  end)

  it("should restore all deleted annotations in bulk", function()
    readerui.annotation.annotations = {}
    local deleted_items = {
      { page = 1, pos0 = "p1", pos1 = "p2", text = "One", deleted = true },
      { page = 2, pos0 = "p3", pos1 = "p4", text = "Two", deleted = true },
    }

    -- Mock event broadcast tracking
    local event_count = 0
    local old_event_new = require("ui/event").new
    require("ui/event").new = function(self_ev, name, ...)
      if name == "AnnotationsModified" then
        event_count = event_count + 1
      end
      return old_event_new(self_ev, name, ...)
    end

    -- 1. Restore all
    sync_instance:restoreAnnotations(deleted_items, true) -- silent

    -- 2. Verify
    assert.is_equal(2, #readerui.annotation.annotations)
    for _, ann in ipairs(readerui.annotation.annotations) do
      assert.is_false(ann.deleted)
    end
    assert.is_equal(
      1,
      event_count,
      "AnnotationsModified event should only be broadcasted once"
    )

    -- Cleanup
    require("ui/event").new = old_event_new
  end)

  it("should clean up sync file for a document", function()
    local tmp_dir = require("datastorage"):getTmpDir()
    local file = readerui.document.file
    local filename = sync_instance.manager:_getAnnotationFilename(file)
    local json_path = tmp_dir .. "/" .. filename
    local sync_path = json_path .. ".sync"

    local f = io.open(json_path, "w")
    f:write("{}")
    f:close()
    f = io.open(sync_path, "w")
    f:write("{}")
    f:close()

    local check_json = io.open(json_path, "r")
    assert.is_not_nil(check_json)
    if check_json then
      check_json:close()
    end
    local check_sync = io.open(sync_path, "r")
    assert.is_not_nil(check_sync)
    if check_sync then
      check_sync:close()
    end

    sync_instance.manager:cleanSyncFile(file)

    assert.is_nil(io.open(json_path, "r"))
    assert.is_nil(io.open(sync_path, "r"))
  end)

  it(
    "should clean orphan sync files while preserving active document and settings",
    function()
      local tmp_dir = require("datastorage"):getTmpDir()
      local active_file = readerui.document.file
      local active_filename =
        sync_instance.manager:_getAnnotationFilename(active_file)
      local active_sync_path = tmp_dir .. "/" .. active_filename .. ".sync"
      local settings_sync_path = tmp_dir .. "/settings_sync.json.sync"
      local orphan_sync_path = tmp_dir
        .. "/deadbeef12345678deadbeef12345678.json.sync"

      local f = io.open(active_sync_path, "w")
      f:write("{}")
      f:close()
      f = io.open(settings_sync_path, "w")
      f:write("{}")
      f:close()
      f = io.open(orphan_sync_path, "w")
      f:write("{}")
      f:close()

      sync_instance.manager:cleanOrphanSyncFiles()

      -- Orphan removed
      local orphan_f = io.open(orphan_sync_path, "r")
      assert.is_nil(orphan_f)

      -- Active and settings preserved
      local active_f = io.open(active_sync_path, "r")
      assert.is_not_nil(active_f)
      if active_f then
        active_f:close()
      end

      local settings_f = io.open(settings_sync_path, "r")
      assert.is_not_nil(settings_f)
      if settings_f then
        settings_f:close()
      end

      -- Cleanup
      os.remove(active_sync_path)
      os.remove(settings_sync_path)
    end
  )
end)
