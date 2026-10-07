describe("AnnotationSync Bookmark Synchronization", function()
  local UIManager, SyncService, DataStorage
  local AnnotationSyncPlugin, test_utils, json, util, annotations_mod
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_bookmark_tmp"
  local old_getDataDir
  local sample_epub = "spec/front/unit/data/juliet.epub"

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    DataStorage = require("datastorage")
    json = require("json")
    util = require("util")
    annotations_mod = require("plugins/AnnotationSync.koplugin/annotations")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server" })
    )

    readerui, sync_instance =
      test_utils.init_integration_context(sample_epub, AnnotationSyncPlugin)
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
    os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))
    os.remove(sync_instance.manager:changedDocumentsFile())
    test_utils.mock_sync_service(SyncService)
  end)

  it("tracks dog-ear bookmarks and persists changed state", function()
    readerui.rolling:onGotoPage(5)
    fastforward_ui_events()

    -- Toggle bookmark
    readerui.bookmark:onToggleBookmark()

    assert.is_equal(1, #readerui.annotation.annotations)
    local bm = readerui.annotation.annotations[1]
    assert.truthy(bm.page)
    assert.falsy(bm.pos0) -- bookmarks don't have coordinates

    local count, docs = sync_instance.manager:getPendingChangedDocuments()
    assert.is_equal(1, count)
    assert.truthy(util.arrayContains(docs, readerui.document.file))
  end)

  it("merges disjoint local and remote bookmarks", function()
    -- Local bookmark on page 5
    readerui.rolling:onGotoPage(5)
    fastforward_ui_events()
    readerui.bookmark:onToggleBookmark()
    local bm_l = readerui.annotation.annotations[1]
    bm_l.datetime = "2026-02-01 10:00:00"

    -- Remote bookmark on page 10
    local bm_r = {
      page = readerui.document:getPageXPointer(10),
      text = "Remote Bookmark",
      datetime = "2026-02-01 11:00:00",
    }
    local income_path = test_utils.write_mock_json(
      test_data_dir,
      "income_bm.json",
      { bm_r }
    )

    SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
      local cached_dest = local_path .. ".sync"
      callback(local_path, cached_dest, income_path)
      local ffiutil = require("ffi/util")
      ffiutil.copyFile(local_path, cached_dest)
      if finish_cb then
        finish_cb(true)
      end
      return true
    end

    sync_instance:manualSync()
    os.remove(income_path)

    assert.is_equal(2, #readerui.annotation.annotations)
  end)

  it("identifies deleted bookmarks correctly (unit test)", function()
    local local_file =
      test_utils.write_mock_json(test_data_dir, "bm_local.json", {
        { page = 2, text = "I am still here" },
      })
    local last_sync_file =
      test_utils.write_mock_json(test_data_dir, "bm_last.json", {
        { page = 1, text = "I was deleted" },
        { page = 2, text = "I am still here" },
      })
    local income_file =
      test_utils.write_mock_json(test_data_dir, "bm_income.json", {
        { page = 1, text = "I was deleted" },
        { page = 2, text = "I am still here" },
      })

    local ok, active = annotations_mod.sync_callback(
      local_file,
      last_sync_file,
      income_file,
      false
    )

    assert.is_true(ok)
    assert.is_equal(1, #active)
    assert.is_equal(2, active[1].page)

    local f = io.open(local_file, "r")
    local disk_list = json.decode(f:read("*a"))
    f:close()

    assert.is_equal(2, #disk_list)
    assert.is_equal(1, disk_list[1].page)
    assert.is_true(
      disk_list[1].deleted,
      "Deleted bookmark should be marked deleted"
    )
    assert.is_equal(2, disk_list[2].page)
    assert.falsy(
      disk_list[2].deleted,
      "Active bookmark should NOT be marked deleted"
    )
  end)

  it("synchronizes bookmark deletions (with safety check bypassed)", function()
    -- 1. Create two bookmarks using XPointers and sync them
    local bm1 =
      { page = "/page1", text = "Bookmark 1", datetime = "2026-02-01 10:00:00" }

    local bm2 =
      { page = "/page2", text = "Bookmark 2", datetime = "2026-02-01 10:00:00" }

    -- Start with both in UI
    readerui.annotation.annotations = { bm1, bm2 }
    sync_instance:manualSync()

    -- 2. Delete one bookmark locally (bm1), keep bm2
    readerui.annotation.annotations = { bm2 }

    -- 3. Mock remote (still has both)
    local income_path = test_utils.write_mock_json(
      test_data_dir,
      "income_del_bm.json",
      { bm1, bm2 }
    )

    local captured_json
    SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
      -- The callback updates local_path with merged data (including deletions)
      local cached_dest = local_path .. ".sync"
      local success = callback(local_path, cached_dest, income_path)

      local f = io.open(local_path, "r")
      captured_json = json.decode(f:read("*all"))
      f:close()

      local ffiutil = require("ffi/util")
      ffiutil.copyFile(local_path, cached_dest)
      if finish_cb then
        finish_cb(success)
      end
      return success
    end

    sync_instance:manualSync()
    os.remove(income_path)

    -- Verify bm1 was marked deleted and uploaded
    assert.is_equal(2, #captured_json)
    local c_bm1, c_bm2
    for _, item in ipairs(captured_json) do
      if item.page == "/page1" then
        c_bm1 = item
      elseif item.page == "/page2" then
        c_bm2 = item
      end
    end
    assert.truthy(c_bm1, "bm1 should exist in sync json")
    assert.is_true(
      c_bm1.deleted,
      "bm1 should be marked as deleted"
    )

    -- Verify bm2 is still there and NOT deleted
    assert.truthy(c_bm2)
    assert.falsy(c_bm2.deleted)

    -- Verify final state in UI is 1 bookmark (bm2)
    assert.is_equal(1, #readerui.annotation.annotations)
    assert.is_equal(bm2.page, readerui.annotation.annotations[1].page)
  end)

  it("accepts remote bookmark deletions", function()
    -- 1. Create a bookmark locally
    readerui.rolling:onGotoPage(5)
    fastforward_ui_events()
    readerui.bookmark:onToggleBookmark()
    local bm = readerui.annotation.annotations[1]
    bm.datetime = "2026-02-01 10:00:00"

    -- 2. Mock remote DELETION (newer timestamp)
    local bm_del = util.tableDeepCopy(bm)
    bm_del.deleted = true
    bm_del.datetime_updated = "2026-02-01 11:00:00"

    local income_path = test_utils.write_mock_json(
      test_data_dir,
      "income_rem_del.json",
      { bm_del }
    )

    local sdr_cached_path =
      sync_instance.manager:getSyncCachePath(readerui.document.file)
    local fc = io.open(sdr_cached_path, "w")
    fc:write(json.encode({ bm }))
    fc:close()

    SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
      local cached_dest = local_path .. ".sync"
      local result = callback(local_path, cached_dest, income_path)
      if result then
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
      end
      if finish_cb then
        finish_cb(result)
      end
      return result
    end

    sync_instance:manualSync()
    os.remove(income_path)

    -- Verify final state is 0 bookmarks (deleted by remote)
    assert.is_equal(0, #readerui.annotation.annotations)
  end)

  it("synchronizes PDF bookmarks correctly", function()
    -- 1. Switch to PDF
    readerui:onClose()
    local sample_pdf = DataStorage:getDataDir() .. "/test_bm.pdf"
    require("ffi/util").copyFile("spec/front/unit/data/sample.pdf", sample_pdf)

    readerui, sync_instance =
      test_utils.init_integration_context(sample_pdf, AnnotationSyncPlugin)
    UIManager:show(readerui)
    fastforward_ui_events()

    -- 2. Toggle bookmark on page 10
    readerui.paging:onGotoPage(10)
    fastforward_ui_events()
    readerui.bookmark:onToggleBookmark()

    assert.is_equal(1, #readerui.annotation.annotations)
    local bm_l = readerui.annotation.annotations[1]
    assert.is_equal(10, bm_l.page)

    -- 3. Mock remote bookmark on page 20
    local bm_r = {
      page = 20,
      text = "Remote PDF Bookmark",
      datetime = "2026-02-01 11:00:00",
    }

    local income_path = test_utils.write_mock_json(
      test_data_dir,
      "income_pdf_bm.json",
      { bm_r }
    )

    os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))

    SyncService.sync = function(server, local_path, callback, upload_only, finish_cb)
      local cached_dest = local_path .. ".sync"
      local result = callback(local_path, cached_dest, income_path)
      if result then
        local ffiutil = require("ffi/util")
        ffiutil.copyFile(local_path, cached_dest)
      end
      if finish_cb then
        finish_cb(result)
      end
      return result
    end

    sync_instance:manualSync()
    os.remove(income_path)
    os.remove(sample_pdf)

    -- 4. Verify both are present
    assert.is_equal(2, #readerui.annotation.annotations)
  end)
end)
