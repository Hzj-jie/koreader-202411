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

  before_each(function()
    readerui.annotation.annotations = {}
  end)

  it(
    "should correctly identify deleted annotations in the sync JSON",
    function()
      -- 1. Setup a sync JSON with one deleted item in persistent sync cache
      local sync_cache_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)

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

      local f = io.open(sync_cache_path, "w")
      if not f then
        error("Could not open " .. sync_cache_path)
      end
      f:write(json.encode(mock_data))
      f:close()

      -- 2. Check getDeletedAnnotations
      local deleted =
        sync_instance.manager:getDeletedAnnotations(readerui.document)
      assert.is_equal(1, #deleted)
      assert.is_equal("Deleted", deleted[1].text)
      assert.is_true(deleted[1].deleted)

      os.remove(sync_cache_path)
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
    local sync_cache_path = sync_instance.manager:getSyncCachePath(file)

    local f = io.open(json_path, "w")
    f:write("{}")
    f:close()
    f = io.open(sync_cache_path, "w")
    f:write("{}")
    f:close()

    local check_json = io.open(json_path, "r")
    assert.is_not_nil(check_json)
    if check_json then
      check_json:close()
    end
    local check_sync = io.open(sync_cache_path, "r")
    assert.is_not_nil(check_sync)
    if check_sync then
      check_sync:close()
    end

    sync_instance.manager:cleanSyncFile(file)

    assert.is_nil(io.open(json_path, "r"))
    assert.is_nil(io.open(sync_cache_path, "r"))
  end)

  it(
    "should clean all orphan sync and temp files from tmp directory",
    function()
      local tmp_dir = require("datastorage"):getTmpDir()
      local orphan_sync_1 = tmp_dir .. "/doc1.json.sync"
      local orphan_sync_2 = tmp_dir .. "/settings_sync.json.sync"
      local orphan_temp = tmp_dir .. "/doc1.json.temp"
      local unrelated_file = tmp_dir .. "/keep_me.txt"

      local f = io.open(orphan_sync_1, "w")
      f:write("{}")
      f:close()
      f = io.open(orphan_sync_2, "w")
      f:write("{}")
      f:close()
      f = io.open(orphan_temp, "w")
      f:write("{}")
      f:close()
      f = io.open(unrelated_file, "w")
      f:write("important")
      f:close()

      sync_instance.manager:cleanOrphanSyncFiles()

      -- All temporary sync and temp files removed
      local f1 = io.open(orphan_sync_1, "r")
      assert.is_nil(f1)
      local f2 = io.open(orphan_sync_2, "r")
      assert.is_nil(f2)
      local ft = io.open(orphan_temp, "r")
      assert.is_nil(ft)

      -- Unrelated file preserved
      local fu = io.open(unrelated_file, "r")
      assert.is_not_nil(fu)
      if fu then
        fu:close()
      end

      -- Cleanup
      os.remove(unrelated_file)
    end
  )

  it(
    "should not list restored annotations as deleted (menu ghosting prevention)",
    function()
      local sync_cache_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local mock_data = {
        ["p1||p2"] = {
          page = 1,
          pos0 = "p1",
          pos1 = "p2",
          text = "Restored Item",
          deleted = true,
        },
      }
      local f = io.open(sync_cache_path, "w")
      f:write(json.encode(mock_data))
      f:close()

      local deleted =
        sync_instance.manager:getDeletedAnnotations(readerui.document)
      assert.is_equal(1, #deleted)

      sync_instance:restoreAnnotation(deleted[1], true)

      local still_deleted =
        sync_instance.manager:getDeletedAnnotations(readerui.document)
      assert.is_equal(0, #still_deleted)

      os.remove(sync_cache_path)
    end
  )

  it(
    "should flush restored annotations into upload payload during next sync",
    function()
      local ann = {
        page = 1,
        pos0 = "p1",
        pos1 = "p2",
        text = "Restored Note",
        deleted = true,
        datetime_updated = "2026-01-01 12:00:00",
      }
      local sync_cache_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local f = io.open(sync_cache_path, "w")
      f:write(json.encode({ ["p1||p2"] = ann }))
      f:close()

      local deleted =
        sync_instance.manager:getDeletedAnnotations(readerui.document)
      assert.is_equal(1, #deleted)
      sync_instance:restoreAnnotation(deleted[1], true)

      local uploaded_content
      local old_sync = SyncService.sync
      SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
        local f_local = io.open(local_path, "r")
        uploaded_content = json.decode(f_local:read("*all"))
        f_local:close()
        if finish_cb then
          finish_cb(true)
        end
        return true
      end

      sync_instance:manualSync()

      assert.is_not_nil(uploaded_content)
      assert.is_not_nil(uploaded_content["p1||p2"])
      assert.is_false(uploaded_content["p1||p2"].deleted)

      SyncService.sync = old_sync
      os.remove(sync_cache_path)
    end
  )
end)
