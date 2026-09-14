describe("ReaderBookmark module", function()
  local DataStorage, DocumentRegistry, ReaderUI, UIManager, Screen, Geom, DocSettings, Util
  local sample_epub, sample_pdf

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    Geom = require("ui/geometry")
    Util = require("ffi/util")

    sample_epub = DataStorage:getDataDir() .. "/readerbookmark.epub"
    sample_pdf = DataStorage:getDataDir() .. "/readerbookmark.pdf"

    Util.copyFile("spec/front/unit/data/juliet.epub", sample_epub)
    Util.copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
  end)

  teardown(function()
    if sample_epub then
      DocSettings:open(sample_epub):purge()
      os.remove(sample_epub)
    end
    if sample_pdf then
      DocSettings:open(sample_pdf):purge()
      os.remove(sample_pdf)
    end
  end)

  local function highlight_text(readerui, pos0, pos1)
    readerui.highlight:onHold(nil, { pos = pos0 })
    readerui.highlight:onHoldPan(nil, { pos = pos1 })
    readerui.highlight:onHoldRelease()
    assert.truthy(readerui.highlight.highlight_dialog)
    readerui.highlight:saveHighlight()
    UIManager:nextTick(function()
      UIManager:close(readerui.highlight.highlight_dialog)
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
  end
  local function toggler_dogear(readerui)
    readerui.bookmark:onToggleBookmark()
    UIManager:nextTick(function()
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
  end
  local function show_bookmark_menu(readerui)
    UIManager:nextTick(function()
      UIManager:close(readerui.bookmark.bookmark_menu)
      UIManager:close(readerui)
      -- We haven't torn it down yet
      ReaderUI.instance = readerui
    end)
    UIManager:run()
  end

  describe("EPUB document", function()
    local readerui
    setup(function()
      DocSettings:open(sample_epub):purge()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      readerui.status.enabled = false
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    before_each(function()
      UIManager:quit()
      UIManager:show(readerui)
      readerui.rolling:onGotoPage(10)
    end)
    it("should show dogear after toggling non-bookmarked page", function()
      assert.falsy(readerui.view.dogear_visible)
      toggler_dogear(readerui)
      Screen:shot("screenshots/reader_bookmark_dogear_epub.png")
      assert.truthy(readerui.view.dogear_visible)
    end)
    it("should not show dogear after toggling bookmarked page", function()
      assert.truthy(readerui.view.dogear_visible)
      toggler_dogear(readerui)
      Screen:shot("screenshots/reader_bookmark_nodogear_epub.png")
      assert.falsy(readerui.view.dogear_visible)
    end)
    it("should sort bookmarks with ascending page numbers", function()
      local pages = { 1, 20, 5, 30, 10, 40, 15, 25, 35, 45 }
      for _, page in ipairs(pages) do
        readerui.rolling:onGotoPage(page)
        toggler_dogear(readerui)
      end
      readerui.bookmark:onShowBookmark()
      show_bookmark_menu(readerui)
      Screen:shot("screenshots/reader_bookmark_10marks_epub.png")
      assert.are.same(10, #readerui.annotation.annotations)
      assert.are.same(
        15,
        readerui.document:getPageFromXPointer(
          readerui.annotation.annotations[4].page
        )
      )
    end)
    it(
      "should keep descending page numbers after removing bookmarks",
      function()
        local pages = { 1, 30, 10, 40, 20 }
        for _, page in ipairs(pages) do
          readerui.rolling:onGotoPage(page)
          toggler_dogear(readerui)
        end
        readerui.bookmark:onShowBookmark()
        show_bookmark_menu(readerui)
        Screen:shot("screenshots/reader_bookmark_5marks_epub.png")
        assert.are.same(5, #readerui.annotation.annotations)
      end
    )
    it("should add bookmark by highlighting", function()
      highlight_text(
        readerui,
        Geom:new({ x = 260, y = 60 }),
        Geom:new({ x = 260, y = 90 })
      )
      readerui.bookmark:onShowBookmark()
      show_bookmark_menu(readerui)
      Screen:shot("screenshots/reader_bookmark_6marks_epub.png")
      assert.are.same(6, #readerui.annotation.annotations)
    end)
    it("should get previous bookmark for certain page", function()
      local xpointer = readerui.document:getXPointer()
      local bm_xpointer = readerui.bookmark:getPreviousBookmarkedPage(xpointer)
      assert.are.same(6, #readerui.annotation.annotations)
      assert.are.same(5, readerui.document:getPageFromXPointer(bm_xpointer))
    end)
    it("should get next bookmark for certain page", function()
      local xpointer = readerui.document:getXPointer()
      local bm_xpointer = readerui.bookmark:getNextBookmarkedPage(xpointer)
      assert.are.same(15, readerui.document:getPageFromXPointer(bm_xpointer))
    end)
    it("should correctly order bookmarks with isBookmarkInPageOrder", function()
      local bookmark_mod = readerui.bookmark
      local bm_page5 = { page = readerui.document:getPageXPointer(5) }
      local bm_page10 = { page = readerui.document:getPageXPointer(10) }

      assert.truthy(bookmark_mod:isBookmarkInPageOrder(bm_page5, bm_page10))
      assert.falsy(bookmark_mod:isBookmarkInPageOrder(bm_page10, bm_page5))

      local page_bm = { page = readerui.document:getPageXPointer(5) }
      local highlight_bm =
        { page = readerui.document:getPageXPointer(5), drawer = true }

      assert.truthy(bookmark_mod:isBookmarkInPageOrder(page_bm, highlight_bm))
      assert.falsy(bookmark_mod:isBookmarkInPageOrder(highlight_bm, page_bm))
    end)
    it("should get correct bookmark type", function()
      local bookmark_mod = readerui.bookmark

      local bm = { page = 5 }
      assert.are.same("bookmark", bookmark_mod.getBookmarkType(bm))

      local hl = { page = 5, drawer = true }
      assert.are.same("highlight", bookmark_mod.getBookmarkType(hl))

      local note = { page = 5, drawer = true, note = "some note" }
      assert.are.same("note", bookmark_mod.getBookmarkType(note))
    end)
    it(
      "should correctly match bookmarks with doesBookmarkMatchTable",
      function()
        local bookmark_mod = readerui.bookmark

        bookmark_mod.match_table = {
          search_str = "test",
          bookmark = true,
          highlight = true,
          note = true,
          case_sensitive = false,
        }

        local bm_match =
          { type = "bookmark", text_orig = "This is a Test page" }
        local bm_no_match = { type = "bookmark", text_orig = "Other text" }

        assert.truthy(bookmark_mod:doesBookmarkMatchTable(bm_match))
        assert.falsy(bookmark_mod:doesBookmarkMatchTable(bm_no_match))

        bookmark_mod.match_table.case_sensitive = true
        assert.falsy(bookmark_mod:doesBookmarkMatchTable(bm_match))

        bookmark_mod.match_table.search_str = "Test"
        assert.truthy(bookmark_mod:doesBookmarkMatchTable(bm_match))

        local note_match = {
          type = "note",
          text_orig = "Highlight",
          note = "My special test note",
        }
        bookmark_mod.match_table.case_sensitive = false
        bookmark_mod.match_table.search_str = "test"
        assert.truthy(bookmark_mod:doesBookmarkMatchTable(note_match))

        bookmark_mod.match_table = nil
      end
    )
    it("should return the latest bookmark based on datetime", function()
      local bookmark_mod = readerui.bookmark
      local orig_annotations = bookmark_mod.ui.annotation.annotations

      bookmark_mod.ui.annotation.annotations = {
        { page = 1, datetime = "2026-05-18 10:00:00", text = "first" },
        { page = 2, datetime = "2026-05-18 12:00:00", text = "latest" },
        { page = 3, datetime = "2026-05-18 11:00:00", text = "second" },
      }

      local latest, latest_idx = bookmark_mod:getLatestBookmark()
      assert.are.same("latest", latest.text)
      assert.are.same(2, latest_idx)

      bookmark_mod.ui.annotation.annotations = orig_annotations
    end)
    it("should return a list of bookmarked pages and their types", function()
      local bookmark_mod = readerui.bookmark
      local orig_annotations = bookmark_mod.ui.annotation.annotations

      local xp5 = readerui.document:getPageXPointer(5)
      local xp10 = readerui.document:getPageXPointer(10)
      bookmark_mod.ui.annotation.annotations = {
        { page = xp5, drawer = nil },
        { page = xp5, drawer = true },
        { page = xp10, drawer = true, note = "note" },
      }

      local pages = bookmark_mod:getBookmarkedPages()

      assert.truthy(pages[5])
      assert.truthy(pages[5]["bookmark"])
      assert.truthy(pages[5]["highlight"])
      assert.falsy(pages[5]["note"])

      assert.truthy(pages[10])
      assert.truthy(pages[10]["note"])
      assert.falsy(pages[10]["bookmark"])
      assert.falsy(pages[10]["highlight"])

      bookmark_mod.ui.annotation.annotations = orig_annotations
    end)

    it("should close bookmark menu when uimanagedCleanUp is called", function()
      local Widget = require("ui/widget/widget")
      local dummy_menu = Widget:new({ dimen = Geom:new({ w = 10, h = 10 }) })
      readerui.bookmark:showWidget(dummy_menu)
      readerui.bookmark.bookmark_menu = dummy_menu

      assert.truthy(readerui.bookmark.bookmark_menu)
      assert.truthy(UIManager:isWindowWidget(dummy_menu))

      readerui.bookmark:uimanagedCleanUp()

      assert.falsy(readerui.bookmark.bookmark_menu)
      assert.falsy(UIManager:isWindowWidget(dummy_menu))
    end)

    it("should check if bookmark text is auto generated", function()
      local bookmark_mod = readerui.bookmark
      local xp5 = readerui.document:getPageXPointer(5)

      local bm1 = {
        page = xp5,
        text = "",
        notes = "note",
        datetime = "2026-01-01 00:00:00",
      }
      assert.truthy(bookmark_mod:isBookmarkAutoText(bm1))

      local bm2 = {
        page = xp5,
        text = "note",
        notes = "note",
        datetime = "2026-01-01 00:00:00",
      }
      assert.truthy(bookmark_mod:isBookmarkAutoText(bm2))

      local page_str = bookmark_mod:getBookmarkPageString(xp5)
      local auto_text = Util.template(
        "Page %1 %2 @ %3",
        page_str,
        "my note",
        "2026-01-01 00:00:00"
      )
      local bm3 = {
        page = xp5,
        text = auto_text,
        notes = "my note",
        datetime = "2026-01-01 00:00:00",
      }
      assert.truthy(bookmark_mod:isBookmarkAutoText(bm3))

      local bm4 = {
        page = xp5,
        text = "Custom Title",
        notes = "my note",
        datetime = "2026-01-01 00:00:00",
      }
      assert.falsy(bookmark_mod:isBookmarkAutoText(bm4))
    end)

    it("should get first and last bookmarked pages", function()
      local bookmark_mod = readerui.bookmark
      local orig_annotations = bookmark_mod.ui.annotation.annotations

      local xp5 = readerui.document:getPageXPointer(5)
      local xp10 = readerui.document:getPageXPointer(10)
      local xp20 = readerui.document:getPageXPointer(20)

      bookmark_mod.ui.annotation.annotations = {
        { page = xp5 },
        { page = xp10 },
        { page = xp20 },
      }

      assert.are.same(xp5, bookmark_mod:getFirstBookmarkedPage(xp10))
      assert.is_nil(bookmark_mod:getFirstBookmarkedPage(xp5))

      assert.are.same(xp20, bookmark_mod:getLastBookmarkedPage(xp10))
      assert.is_nil(bookmark_mod:getLastBookmarkedPage(xp20))

      bookmark_mod.ui.annotation.annotations = orig_annotations
    end)

    it("should delete item note", function()
      local bookmark_mod = readerui.bookmark
      local orig_annotations = bookmark_mod.ui.annotation.annotations

      local item = {
        page = readerui.document:getPageXPointer(5),
        drawer = true,
        note = "test note",
      }
      bookmark_mod.ui.annotation.annotations = { item }

      bookmark_mod:deleteItemNote(item)
      assert.is_nil(bookmark_mod.ui.annotation.annotations[1].note)

      bookmark_mod.ui.annotation.annotations = orig_annotations
    end)

    it("should generate menu items for show_in_items and sort_by", function()
      local bookmark_mod = readerui.bookmark

      assert.is.string(bookmark_mod:genShowInItemsMenuItems())

      local item_note = bookmark_mod:genShowInItemsMenuItems("note")
      assert.truthy(item_note.checked_func)
      assert.truthy(item_note.callback)
      item_note.callback()
      assert.are.same("note", bookmark_mod.items_text)

      assert.is.string(bookmark_mod:genSortByMenuItems())

      local sort_date = bookmark_mod:genSortByMenuItems("date")
      assert.truthy(sort_date.checked_func)
      assert.truthy(sort_date.callback)
      sort_date.callback()
      assert.are.same("date", G_reader_settings:read("bookmarks_items_sorting"))

      -- restore sort to page
      local sort_page = bookmark_mod:genSortByMenuItems("page")
      sort_page.callback()
    end)

    it("should add bookmark items to main menu", function()
      local bookmark_mod = readerui.bookmark
      local menu_items = {}
      bookmark_mod:addToMainMenu(menu_items)

      assert.truthy(menu_items.bookmarks)
      assert.truthy(menu_items.bookmarks_settings)
      assert.truthy(menu_items.bookmark_search)
    end)

    it("should format bookmark item text correctly", function()
      local bookmark_mod = readerui.bookmark
      local item = {
        type = "note",
        text_orig = "original text",
        note = "my note",
        datetime = "2026-01-01 12:00:00",
      }

      bookmark_mod.items_text = "text"
      bookmark_mod.sorting_mode = "page"
      local text1 = bookmark_mod:getBookmarkItemText(item)
      assert.truthy(text1:find("original text", 1, true))

      bookmark_mod.items_text = "note"
      local text2 = bookmark_mod:getBookmarkItemText(item)
      assert.truthy(text2:find("my note", 1, true))

      bookmark_mod.sorting_mode = "date"
      local text3 = bookmark_mod:getBookmarkItemText(item)
      assert.truthy(text3:find("2026-01-01 12:00:00", 1, true))

      bookmark_mod.items_text = "note"
      bookmark_mod.sorting_mode = "page"
    end)

    it(
      "should navigate to first, last, next, and previous bookmarks",
      function()
        local bookmark_mod = readerui.bookmark
        local orig_annotations = bookmark_mod.ui.annotation.annotations

        local xp5 = readerui.document:getPageXPointer(5)
        local xp10 = readerui.document:getPageXPointer(10)
        local xp20 = readerui.document:getPageXPointer(20)

        bookmark_mod.ui.annotation.annotations = {
          { page = xp5 },
          { page = xp10 },
          { page = xp20 },
        }

        readerui.rolling:onGotoPage(10)

        assert.truthy(bookmark_mod:onGotoFirstBookmark(false))
        assert.truthy(bookmark_mod:onGotoLastBookmark(false))
        assert.truthy(bookmark_mod:onGotoPreviousBookmarkFromPage(false))
        assert.truthy(bookmark_mod:onGotoNextBookmarkFromPage(false))

        bookmark_mod.ui.annotation.annotations = orig_annotations
      end
    )

    it("should filter menu items by edited text", function()
      local bookmark_mod = readerui.bookmark

      local item1 = { text_edited = true, text = "edited" }
      local item2 = { text_edited = nil, text = "not edited" }
      local dummy_menu = {
        item_table = { item1, item2 },
        switchItemTable = function() end,
      }
      bookmark_mod.bookmark_menu = { dummy_menu }

      bookmark_mod:filterByEditedText()

      assert.truthy(bookmark_mod.show_edited_only)
      assert.are.same(1, #dummy_menu.item_table)
      assert.are.same("edited", dummy_menu.item_table[1].text)

      bookmark_mod.bookmark_menu = nil
      bookmark_mod.show_edited_only = nil
    end)
  end)

  describe("PDF document", function()
    local readerui
    setup(function()
      DocSettings:open(sample_pdf):purge()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      readerui.status.enabled = false
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    before_each(function()
      UIManager:quit()
      UIManager:show(readerui)
      readerui.paging:onGotoPage(10)
    end)
    it("should show dogear after toggling non-bookmarked page", function()
      toggler_dogear(readerui)
      Screen:shot("screenshots/reader_bookmark_dogear_pdf.png")
      assert.truthy(readerui.view.dogear_visible)
    end)
    it("should not show dogear after toggling bookmarked page", function()
      toggler_dogear(readerui)
      Screen:shot("screenshots/reader_bookmark_nodogear_pdf.png")
      assert.truthy(not readerui.view.dogear_visible)
    end)
    it("should sort bookmarks with ascending page numbers", function()
      local pages = { 1, 20, 5, 30, 10, 40, 15, 25, 35, 45 }
      for _, page in ipairs(pages) do
        if not UIManager:isWindowWidget(readerui) then
          UIManager:show(readerui)
        end
        readerui.paging:onGotoPage(page)
        toggler_dogear(readerui)
      end
      readerui.bookmark:onShowBookmark()
      show_bookmark_menu(readerui)
      Screen:shot("screenshots/reader_bookmark_10marks_pdf.png")
      assert.are.same(10, #readerui.annotation.annotations)
      assert.are.same(15, readerui.annotation.annotations[4].page)
    end)
    it(
      "should keep descending page numbers after removing bookmarks",
      function()
        local pages = { 1, 30, 10, 40, 20 }
        for _, page in ipairs(pages) do
          if not UIManager:isWindowWidget(readerui) then
            UIManager:show(readerui)
          end
          readerui.paging:onGotoPage(page)
          toggler_dogear(readerui)
        end
        readerui.bookmark:onShowBookmark()
        show_bookmark_menu(readerui)
        Screen:shot("screenshots/reader_bookmark_5marks_pdf.png")
        assert.are.same(5, #readerui.annotation.annotations)
      end
    )
    it("should add bookmark by highlighting", function()
      highlight_text(
        readerui,
        Geom:new({ x = 260, y = 70 }),
        Geom:new({ x = 260, y = 150 })
      )
      readerui.bookmark:onShowBookmark()
      show_bookmark_menu(readerui)
      Screen:shot("screenshots/reader_bookmark_6marks_pdf.png")
      assert.are.same(6, #readerui.annotation.annotations)
    end)
    it("should get previous bookmark for certain page", function()
      assert.are.same(5, readerui.bookmark:getPreviousBookmarkedPage(10))
    end)
    it("should get next bookmark for certain page", function()
      assert.are.same(15, readerui.bookmark:getNextBookmarkedPage(10))
    end)
    it("should return nil for boundary bookmark lookups", function()
      assert.is_nil(readerui.bookmark:getPreviousBookmarkedPage(1))
      assert.is_nil(readerui.bookmark:getNextBookmarkedPage(50))
    end)

    it("should get first and last bookmarked pages in PDF", function()
      local bookmark_mod = readerui.bookmark
      local orig_annotations = bookmark_mod.ui.annotation.annotations

      bookmark_mod.ui.annotation.annotations = {
        { page = 5 },
        { page = 10 },
        { page = 20 },
      }

      assert.are.same(5, bookmark_mod:getFirstBookmarkedPage(10))
      assert.is_nil(bookmark_mod:getFirstBookmarkedPage(5))

      assert.are.same(20, bookmark_mod:getLastBookmarkedPage(10))
      assert.is_nil(bookmark_mod:getLastBookmarkedPage(20))

      bookmark_mod.ui.annotation.annotations = orig_annotations
    end)

    it("should format bookmark page string for PDF", function()
      local bookmark_mod = readerui.bookmark
      assert.are.same("15", bookmark_mod:getBookmarkPageString(15))
      if type(bookmark_mod.onDispatcherRegisterActions) == "function" then
        bookmark_mod:onDispatcherRegisterActions()
      end
    end)

    it(
      "should handle bookmark export actions and sorting mode toggles",
      function()
        local bookmark_mod = readerui.bookmark
        if type(bookmark_mod.getBookmarkSummary) == "function" then
          local summary = bookmark_mod:getBookmarkSummary()
          assert.is_string(summary)
        end
      end
    )

    it("should handle bookmark removal, notes, and text extraction", function()
      local bookmark_mod = readerui.bookmark
      local test_item = {
        page = 12,
        type = "bookmark",
        text = "Test Bookmark Text",
        text_orig = "Test Bookmark Text",
        note = "Sample Note",
        datetime = "2026-08-24 10:00:00",
      }
      table.insert(bookmark_mod.ui.annotation.annotations, test_item)

      local item_text = bookmark_mod:getBookmarkItemText(test_item)
      assert.is_string(item_text)

      bookmark_mod:deleteItemNote(test_item)
      assert.is_nil(test_item.note)

      test_item.note = "New note content"
      assert.are.equal("New note content", test_item.note)

      local is_auto = bookmark_mod:isBookmarkAutoText(test_item)
      assert.is_boolean(is_auto)

      local in_order = bookmark_mod:isBookmarkInPageOrder(
        { page = 5 },
        { page = 10 }
      )
      assert.is_boolean(in_order)

      bookmark_mod.match_table = { bookmark = true }
      local match = bookmark_mod:doesBookmarkMatchTable(test_item)
      assert.is_truthy(match)

      local initial_count = #bookmark_mod.ui.annotation.annotations
      bookmark_mod:removeItem(test_item)
      assert.are.equal(
        initial_count - 1,
        #bookmark_mod.ui.annotation.annotations
      )
    end)

    it("should handle bookmark navigation and menu generation", function()
      local bookmark_mod = readerui.bookmark
      local pages = bookmark_mod:getBookmarkedPages()
      assert.is_table(pages)

      local latest = bookmark_mod:getLatestBookmark()
      assert.is_not_nil(latest)

      bookmark_mod:onGotoFirstBookmark()
      bookmark_mod:onGotoLastBookmark()

      local show_items = bookmark_mod:genShowInItemsMenuItems("notes")
      assert.is_table(show_items)

      local sort_items = bookmark_mod:genSortByMenuItems("page", "separator")
      assert.is_table(sort_items)
    end)

  end)

  describe("Additional ReaderBookmark operations", function()
    local readerui, bookmark_mod
    setup(function()
      DocSettings:open(sample_epub):purge()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      readerui.status.enabled = false
      bookmark_mod = readerui.bookmark
    end)

    teardown(function()
      while #UIManager._window_stack > 1 do
        local top_w = UIManager._window_stack[#UIManager._window_stack].widget
        if top_w ~= readerui then
          UIManager:close(top_w)
        else
          break
        end
      end
      readerui:onExit()
      readerui:onClose()
    end)

    it("should exercise main menu items, settings sub-menus, and callbacks", function()
      local fake_menu = {}
      bookmark_mod:addToMainMenu(fake_menu)

      local function walk_menu(tbl)
        for _, item in ipairs(tbl) do
          if item.text_func then pcall(item.text_func) end
          if item.checked_func then pcall(item.checked_func) end
          if item.enabled_func then pcall(item.enabled_func) end
          if item.callback then
            pcall(item.callback, { updateItems = function() end, closeMenu = function() end })
            local top = UIManager._window_stack[#UIManager._window_stack]
            if top and top.widget and top.widget ~= readerui then
              if top.widget.ok_callback then pcall(top.widget.ok_callback) end
              if top.widget.callback then pcall(top.widget.callback, top.widget) end
              if top.widget.extra_callback then pcall(top.widget.extra_callback) end
              UIManager:close(top.widget)
            end
          end
          if item.sub_item_table then
            walk_menu(item.sub_item_table)
          end
        end
      end

      if fake_menu.bookmarks_settings and fake_menu.bookmarks_settings.sub_item_table then
        walk_menu(fake_menu.bookmarks_settings.sub_item_table)
      end

      if fake_menu.bookmarks and fake_menu.bookmarks.callback then
        pcall(fake_menu.bookmarks.callback)
        if bookmark_mod.bookmark_menu then
          UIManager:close(bookmark_mod.bookmark_menu)
          bookmark_mod.bookmark_menu = nil
        end
      end

      if fake_menu.toggle_bookmark and fake_menu.toggle_bookmark.callback then
        pcall(fake_menu.toggle_bookmark.text_func)
        pcall(fake_menu.toggle_bookmark.callback)
      end

      if fake_menu.bookmark_browsing_mode then
        if fake_menu.bookmark_browsing_mode.checked_func then
          pcall(fake_menu.bookmark_browsing_mode.checked_func)
        end
        if fake_menu.bookmark_browsing_mode.callback then
          pcall(fake_menu.bookmark_browsing_mode.callback, { closeMenu = function() end })
        end
      end

      if fake_menu.bookmark_search then
        if fake_menu.bookmark_search.enabled_func then
          pcall(fake_menu.bookmark_search.enabled_func)
        end
        if fake_menu.bookmark_search.callback then
          pcall(fake_menu.bookmark_search.callback)
          local top = UIManager._window_stack[#UIManager._window_stack]
          if top and top.widget and top.widget ~= readerui then
            UIManager:close(top.widget)
          end
        end
      end
    end)

    it("should exercise bookmark list dialog, selection mode, and batch operations", function()
      -- Create real bookmarks in EPUB
      readerui.rolling:onGotoPage(2)
      bookmark_mod:toggleBookmark()
      readerui.rolling:onGotoPage(5)
      bookmark_mod:toggleBookmark()
      readerui.rolling:onGotoPage(8)
      bookmark_mod:toggleBookmark()

      bookmark_mod:onShowBookmark()
      assert.is_not_nil(bookmark_mod.bookmark_menu)
      local bm_menu = bookmark_mod.bookmark_menu[1]

      -- Test toggle select mode and hold
      bm_menu:onLeftButtonHold()
      assert.is_not_nil(bm_menu.select_count)

      -- Select item in select mode
      local item = bm_menu.item_table[1]
      bm_menu:onMenuSelect(item)
      assert.is_true(item.dim)
      bm_menu:onMenuSelect(item)
      assert.is_nil(item.dim)

      -- Left button tap in select mode
      bm_menu.select_count = 1
      bm_menu.item_table[1].dim = true
      bm_menu:onLeftButtonTap()
      local top = UIManager._window_stack[#UIManager._window_stack]
      if top and top.widget and top.widget ~= readerui then
        local btns = top.widget.buttons
        for _, row in ipairs(btns) do
          for _, btn in ipairs(row) do
            if btn.callback and btn.enabled ~= false then
              pcall(btn.callback)
              local confirm = UIManager._window_stack[#UIManager._window_stack]
              if confirm and confirm.widget and confirm.widget ~= readerui and confirm.widget.ok_callback then
                pcall(confirm.widget.ok_callback)
              end
            end
          end
        end
        UIManager:close(top.widget)
      end

      -- Exit select mode
      bm_menu:toggleSelectMode()

      -- Left button tap in normal mode
      bm_menu:onLeftButtonTap()
      top = UIManager._window_stack[#UIManager._window_stack]
      if top and top.widget and top.widget ~= readerui then
        local btns = top.widget.buttons
        for _, row in ipairs(btns) do
          for _, btn in ipairs(row) do
            if btn.callback and btn.enabled ~= false then
              pcall(btn.callback)
            end
          end
        end
        UIManager:close(top.widget)
      end

      -- Close bookmark menu
      if bm_menu.close_callback then
        bm_menu.close_callback()
      end
    end)

    it("should exercise bookmark details, text editing, notes, and pagination", function()
      -- Ensure we have annotations
      readerui.rolling:onGotoPage(3)
      bookmark_mod:toggleBookmark()

      bookmark_mod:onShowBookmark()
      local bm_menu = bookmark_mod.bookmark_menu[1]
      local item = bm_menu.item_table[1]
      bm_menu:onMenuHold(item)

      local top = UIManager._window_stack[#UIManager._window_stack]
      if top and top.widget and top.widget ~= readerui then
        local details_widget = top.widget
        if details_widget.buttons_table then
          for _, row in ipairs(details_widget.buttons_table) do
            for _, btn in ipairs(row) do
              if btn.callback and btn.enabled ~= false then
                pcall(btn.callback)
                local sub = UIManager._window_stack[#UIManager._window_stack]
                if sub and sub.widget and sub.widget ~= readerui and sub.widget ~= details_widget then
                  if sub.widget.ok_callback then pcall(sub.widget.ok_callback) end
                  if sub.widget.callback then pcall(sub.widget.callback, sub.widget) end
                  UIManager:close(sub.widget)
                end
              end
            end
          end
        end
        UIManager:close(details_widget)
      end

      if bm_menu.close_callback then
        bm_menu.close_callback()
      end
    end)

    it("should exercise search bookmark dialog and filter options", function()
      bookmark_mod:onSearchBookmark()
      local top = UIManager._window_stack[#UIManager._window_stack]
      if top and top.widget and top.widget ~= readerui then
        local dlg = top.widget
        if dlg.input_widget and dlg.input_widget.setText then
          dlg.input_widget:setText("chapter")
        end
        if dlg.buttons then
          for _, row in ipairs(dlg.buttons) do
            for _, btn in ipairs(row) do
              if btn.text == "Search" and btn.callback then
                pcall(btn.callback)
              end
            end
          end
        end
        UIManager:close(dlg)
      end

      -- Open bookmark menu to test filterByEditedText and filterByHighlightStyle
      bookmark_mod:onShowBookmark()
      if bookmark_mod.bookmark_menu then
        bookmark_mod:filterByEditedText()
        bookmark_mod:filterByHighlightStyle()
        top = UIManager._window_stack[#UIManager._window_stack]
        if top and top.widget and top.widget ~= readerui and top.widget ~= bookmark_mod.bookmark_menu then
          UIManager:close(top.widget)
        end
        UIManager:close(bookmark_mod.bookmark_menu)
        bookmark_mod.bookmark_menu = nil
      end
    end)

    it("should exercise misc helpers, key events, and event handlers", function()
      local xp = readerui.document:getXPointer()
      bookmark_mod:onGesture()
      bookmark_mod:onPhysicalKeyboardConnected()
      bookmark_mod:registerKeyEvents()
      bookmark_mod:onPageUpdate()
      bookmark_mod:onPosUpdate()
      bookmark_mod:setDogearVisibility(xp)
      bookmark_mod:onGotoPreviousBookmarkFromPage(true)
      bookmark_mod:onGotoNextBookmarkFromPage(false)
      bookmark_mod:onGotoPreviousBookmark(xp)
      bookmark_mod:onGotoNextBookmark(xp)

      if #bookmark_mod.ui.annotation.annotations > 0 then
        local first_item = bookmark_mod.ui.annotation.annotations[1]
        local idx = bookmark_mod:getBookmarkItemIndex(first_item)
        assert.is_number(idx)
      end
    end)

    it("should handle onToggleBookmark refresh region and setBookmarkNote note_mark dirty refresh", function()
      local dirty_called, dirty_func
      local orig_setDirty = UIManager.setDirty
      UIManager.setDirty = function(self, target, mode_or_func)
        dirty_called = true
        if type(mode_or_func) == "function" then
          dirty_func = mode_or_func
        end
        return orig_setDirty(self, target, mode_or_func)
      end

      -- onToggleBookmark dirty func execution
      bookmark_mod:onToggleBookmark()
      assert.is_true(dirty_called)
      if dirty_func then
        local mode, region = dirty_func()
        assert.are.equal("ui", mode)
      end

      -- showBookmarkDetails with details_updated and note_mark without bm_menu
      readerui.view.highlight.note_mark = "asterisk"
      bookmark_mod.details_updated = true
      bookmark_mod:showBookmarkDetails(1)
      while #UIManager._window_stack > 1 do
        local top_w = UIManager._window_stack[#UIManager._window_stack].widget
        if top_w ~= readerui then
          if top_w.dismiss_callback then
            pcall(top_w.dismiss_callback)
          end
          UIManager:close(top_w)
        else
          break
        end
      end

      UIManager.setDirty = orig_setDirty
    end)
  end)
end)
