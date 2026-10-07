describe("AnnotationSync PDF Core Integration", function()
  local ReaderUI, UIManager, SyncService, Geom, DataStorage
  local AnnotationSyncPlugin, highlight_pdf_db, test_utils, json, util, ReaderAnnotation
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_pdf_integration_tmp"
  local old_getDataDir
  local sample_pdf
  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    require("document/canvascontext"):init(require("device"))
    Geom = require("ui/geometry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    SyncService = require("apps/cloudstorage/syncservice")
    DataStorage = require("datastorage")
    json = require("json")
    util = require("util")
    ReaderAnnotation = require("apps/reader/modules/readerannotation")

    highlight_pdf_db =
      require("plugins/AnnotationSync.koplugin/highlight_pdf_db")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    sample_pdf = DataStorage:getDataDir() .. "/test.pdf"
    require("ffi/util").copyFile("spec/front/unit/data/sample.pdf", sample_pdf)

    G_reader_settings:save("cloud_download_dir", "http://mock-server")
    G_reader_settings:save(
      "cloud_server_object",
      json.encode({ url = "http://mock-server", type = "webdav" })
    )
    G_reader_settings:save("default_highlight_action", "highlight")

    readerui, sync_instance =
      test_utils.init_integration_context(sample_pdf, AnnotationSyncPlugin)
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
    sync_instance.settings.last_sync = "Never"
    sync_instance.settings.use_filename = true
    os.remove(sync_instance.manager:getSyncCachePath(readerui.document.file))
    os.remove(sync_instance.manager:changedDocumentsFile())

    test_utils.mock_sync_service(SyncService)
  end)

  local function create_pdf_ann_from_db(index, note, datetime)
    local entry = highlight_pdf_db[index]
    local ann = {
      drawer = "lighten",
      page = entry.page_num,
      pos0 = util.tableDeepCopy(entry.pos0),
      pos1 = util.tableDeepCopy(entry.pos1),
      text = entry.text,
      chapter = "Test Chapter",
      datetime = datetime or "2026-01-01 12:00:00",
      note = note,
    }
    ann.pos0.page = entry.page_num
    ann.pos1.page = entry.page_num

    return ann
  end

  describe("Tracking & Persistence (PDF)", function()
    it("tracks PDF highlights and persists changed state", function()
      readerui.paging:onGotoPage(10)
      fastforward_ui_events()
      test_utils.emulate_highlight(readerui, highlight_pdf_db[1])

      local count, docs = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(1, count)
      assert.truthy(util.arrayContains(docs, readerui.document.file))

      sync_instance:manualSync()
      assert.is_equal(0, (sync_instance.manager:getPendingChangedDocuments()))
    end)
  end)

  describe("Bidirectional Merge & Conflicts (PDF)", function()
    it("merges disjoint local and remote PDF additions", function()
      readerui.paging:onGotoPage(10)
      fastforward_ui_events()
      test_utils.emulate_highlight(readerui, highlight_pdf_db[1])

      local ann2 = create_pdf_ann_from_db(2)
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_disjoint_pdf.json",
        { ann2 }
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

    it(
      "preserves distinct overlapping PDF highlights without collapsing them",
      function()
        -- Local has a highlight
        local entry = highlight_pdf_db[1]
        test_utils.emulate_highlight(readerui, entry)
        local local_ann = readerui.annotation.annotations[1]
        local_ann.datetime = "2026-02-01 10:00:00"
        local_ann.note = "Local Version"

        -- Remote has a distinct highlight on the same page with different coordinates
        local remote_ann = util.tableDeepCopy(local_ann)
        remote_ann.pos1.x = remote_ann.pos1.x + 10 -- Slightly longer
        remote_ann.datetime = "2026-02-01 11:00:00"
        remote_ann.note = "Remote Version"

        local income_path = test_utils.write_mock_json(
          test_data_dir,
          "income_overlap_pdf.json",
          { remote_ann }
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

        -- Both distinct highlights should be preserved (exact coordinate identity avoids data loss)
        assert.is_equal(2, #readerui.annotation.annotations)
      end
    )

    it("resolves PDF conflicts using timestamps (latest wins)", function()
      local ann_l =
        create_pdf_ann_from_db(1, "Local Newer PDF", "2026-02-02 12:00:00")
      table.insert(readerui.annotation.annotations, ann_l)

      local ann_r =
        create_pdf_ann_from_db(1, "Remote Older PDF", "2026-02-01 12:00:00")
      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_conflict_pdf.json",
        { ann_r }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ ann_r }))
      fc:close()

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
      assert.is_equal(
        "Local Newer PDF",
        readerui.annotation.annotations[1].note
      )
    end)
  end)

  describe("Deletion (PDF)", function()
    it("synchronizes PDF deletions bidirectionally", function()
      local ann = create_pdf_ann_from_db(1)
      table.insert(readerui.annotation.annotations, ann)

      local ann_del = util.tableDeepCopy(ann)
      ann_del.deleted = true
      ann_del.datetime_updated = "2026-02-02 12:00:00"

      local income_path = test_utils.write_mock_json(
        test_data_dir,
        "income_del_pdf.json",
        { ann_del }
      )

      local sdr_cached_path =
        sync_instance.manager:getSyncCachePath(readerui.document.file)
      local fc = io.open(sdr_cached_path, "w")
      fc:write(json.encode({ ann }))
      fc:close()

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
      assert.is_equal(0, #readerui.annotation.annotations)
    end)
  end)

  describe("Edge Cases (PDF)", function()
    local old_s2p
    local old_action
    local old_show_menu

    before_each(function()
      old_s2p = readerui.view.screenToPageTransform
      old_action = G_reader_settings:read("default_highlight_action")
      G_reader_settings:save("default_highlight_action", "ask")

      old_show_menu = readerui.highlight.onShowHighlightMenu
      readerui.highlight.onShowHighlightMenu = function(self)
        -- Mock: do nothing, don't show dialog, keep selection
      end
    end)

    after_each(function()
      readerui.document.configurable.text_wrap = 0
      readerui.view.screenToPageTransform = old_s2p
      G_reader_settings:save("default_highlight_action", old_action)
      readerui.highlight.onShowHighlightMenu = old_show_menu
      readerui.annotation.annotations = {}
      readerui.highlight:clear()
    end)

    it("distinguishes PDF highlights on different pages with same X", function()
      local ann1 = create_pdf_ann_from_db(1)
      local ann2 = util.tableDeepCopy(ann1)
      ann2.page = ann1.page + 1
      ann2.pos0.page = ann2.page
      ann2.pos1.page = ann2.page

      assert.is_false(ReaderAnnotation.doesMatch(ann1, ann2))
    end)

    it("distinguishes PDF highlights on different lines with same X", function()
      local ann1 = create_pdf_ann_from_db(1) -- y=60
      local ann2 = util.tableDeepCopy(ann1)
      ann2.pos0.y = ann1.pos0.y + 100 -- different line
      ann2.pos1.y = ann1.pos1.y + 100

      assert.is_false(ReaderAnnotation.doesMatch(ann1, ann2))
    end)

    it("handles PDF highlights in Reflow Mode", function()
      -- Enable Reflow
      readerui.document.configurable.text_wrap = 1
      readerui.paging:onGotoPage(10)
      fastforward_ui_events()

      local pos0 = Geom:new({ x = 300, y = 300 })
      local pos1 = Geom:new({ x = 300, y = 500 })
      readerui.highlight:onHold(nil, { pos = pos0 })
      readerui.highlight:onHoldPan(nil, { pos = pos1 })
      readerui.highlight:onHoldRelease()
      fastforward_ui_events()

      local index = readerui.highlight:saveHighlight()
      assert.truthy(index)
      local ann = readerui.annotation.annotations[index]
      assert.truthy(ann)

      -- Verify it's tracked
      local count, docs = sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(1, count)

      -- Cleanup: DISABLE REFLOW before finishing
      readerui.document.configurable.text_wrap = 0
      readerui.paging:onGotoPage(10)
      fastforward_ui_events()
    end)

    it("handles PDF highlights with Cropping enabled", function()
      -- 1. Get highlight for uncropped
      local entry = highlight_pdf_db[1]
      readerui.paging:onGotoPage(10)
      fastforward_ui_events()

      test_utils.emulate_highlight(readerui, entry)
      local ann_uncropped = readerui.annotation.annotations[1]
      assert.truthy(ann_uncropped)
      readerui.annotation.annotations = {}
      readerui.highlight:clear()

      -- 2. Enable a manual crop (this shifts the screen-to-page transform)
      -- We'll simulate a crop by setting the document's view port or similar
      -- In tests, we can just use readerui.view:setBBox or document settings
      -- Let's try setting manual crop via doc_settings if possible,
      -- or just assume the transform handles it.

      -- A simpler way: we know that if we click the SAME screen coordinates
      -- but the page is "shifted" via a crop, we get different page coordinates.
      -- But KOReader's ReaderHighlight should still produce consistent
      -- PAGE coordinates for the SAME text.

      -- We'll mock a shift in the view's transform if we can't easily trigger a real crop
      readerui.view.screenToPageTransform = function(this, pos)
        local p = old_s2p(this, pos)
        -- Simulate a shift: if we click at (x,y), it's as if we clicked at (x+50, y+50)
        -- because the page is shifted left/up by 50 units.
        p.x = p.x + 50
        p.y = p.y + 50
        return p
      end

      -- Highlight again at the SAME screen coordinates
      test_utils.emulate_highlight(readerui, entry)
      local ann_cropped = readerui.annotation.annotations[1]
      assert.truthy(ann_cropped)

      -- Highlights should differ because we clicked different text (due to simulated crop shift)
      assert.is_false(
        ReaderAnnotation.doesMatch(ann_uncropped, ann_cropped)
      )

      -- Restore transform
      readerui.view.screenToPageTransform = old_s2p
      readerui.annotation.annotations = {}
      readerui.highlight:clear()
    end)
  end)
end)
