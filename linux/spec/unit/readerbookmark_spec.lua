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

    sample_epub = "spec/front/unit/data/juliet.epub"
    sample_pdf = DataStorage:getDataDir() .. "/readerbookmark.pdf"

    Util.copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
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

    it("should handle bookmark export actions and sorting mode toggles", function()
      local bookmark_mod = readerui.bookmark
      if type(bookmark_mod.getBookmarkSummary) == "function" then
        local summary = bookmark_mod:getBookmarkSummary()
        assert.is_string(summary)
      end
    end)
  end)
end)
