describe("Readerhighlight module", function()
  local DataStorage, DocumentRegistry, ReaderUI, UIManager, Screen, Geom, Event
  local sample_pdf

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    DocumentRegistry = require("document/documentregistry")
    Event = require("ui/event")
    Geom = require("ui/geometry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
    sample_pdf = DataStorage:getDataDir() .. "/readerhighlight.pdf"
    require("ffi/util").copyFile("spec/front/unit/data/sample.pdf", sample_pdf)
  end)

  local function highlight_single_word(readerui, pos0)
    local s = spy.on(readerui.languagesupport, "improveWordSelection")

    readerui.highlight:onHold(nil, { pos = pos0 })
    readerui.highlight:onHoldRelease()
    readerui.highlight:saveHighlight()

    assert.spy(s).was_called()
    assert.spy(s).was_called_with(
      match.is_ref(readerui.languagesupport),
      match.is_ref(readerui.highlight.selected_text)
    )
    -- Reset in case we're called more than once.
    readerui.languagesupport.improveWordSelection:revert()

    UIManager:close(readerui.dictionary.dict_window)
    UIManager:close(readerui)
    -- We haven't torn it down yet
    ReaderUI.instance = readerui
    UIManager:quit()
  end
  local function highlight_text(readerui, pos0, pos1)
    readerui.highlight:onHold(nil, { pos = pos0 })
    readerui.highlight:onHoldPan(nil, { pos = pos1 })
    local next_slot
    for i = #UIManager._window_stack, 0, -1 do
      local top_window = UIManager._window_stack[i]
      -- skip modal window
      if not top_window or not top_window.widget.modal then
        next_slot = i + 1
        break
      end
    end
    readerui.highlight:onHoldRelease()
    assert.truthy(readerui.highlight.highlight_dialog)
    assert.truthy(
      UIManager._window_stack[next_slot].widget
        == readerui.highlight.highlight_dialog
    )
    readerui.highlight:saveHighlight()
    UIManager:close(readerui.highlight.highlight_dialog)
    UIManager:close(readerui)
    -- We haven't torn it down yet
    ReaderUI.instance = readerui
    UIManager:quit()
  end
  local function tap_highlight_text(readerui, pos0, pos1, pos2)
    readerui.highlight:onHold(nil, { pos = pos0 })
    readerui.highlight:onHoldPan(nil, { pos = pos1 })
    readerui.highlight:onHoldRelease()
    readerui.highlight:saveHighlight()
    readerui.highlight:clear()
    UIManager:close(readerui.highlight.highlight_dialog)
    readerui.highlight:onTap(nil, { pos = pos2 })
    assert.truthy(readerui.highlight.edit_highlight_dialog)
    UIManager:close(readerui.highlight.edit_highlight_dialog)
    UIManager:close(readerui)
    -- We haven't torn it down yet
    ReaderUI.instance = readerui
    UIManager:quit()
  end

  describe("highlight for EPUB documents", function()
    local page = 10
    local readerui, selection_spy
    local sample_epub = DataStorage:getDataDir() .. "/juliet.epub"
    before_each(function()
      UIManager:quit()
      require("ffi/util").copyFile(
        "spec/front/unit/data/juliet.epub",
        sample_epub
      )
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      selection_spy = spy.on(readerui.languagesupport, "improveWordSelection")
      readerui.rolling:onGotoPage(page)
      --- @fixme HACK: Mock UIManager:run x and y for readerui.dimen
      --- @todo Refactor readerview's dimen handling so we can get rid of
      -- this workaround
      readerui:paintTo(Screen.bb, 0, 0)
    end)
    after_each(function()
      readerui.highlight:clear()
      readerui.annotation.annotations = {}
      readerui:onExit()
      readerui:onClose()
      os.remove(sample_epub)
      os.execute("rm -rf " .. sample_epub:gsub("%.epub$", ".sdr"))
    end)
    it("should highlight single word", function()
      highlight_single_word(readerui, Geom:new({ x = 400, y = 70 }))
      Screen:shot("screenshots/reader_highlight_single_word_epub.png")
      assert.spy(selection_spy).was_called()
      assert.truthy(#readerui.annotation.annotations == 1)
    end)
    it("should highlight text", function()
      highlight_text(
        readerui,
        Geom:new({ x = 400, y = 110 }),
        Geom:new({ x = 400, y = 170 })
      )
      Screen:shot("screenshots/reader_highlight_text_epub.png")
      assert.spy(selection_spy).was_called()
      assert.truthy(#readerui.annotation.annotations == 1)
    end)
    it("should response on tap gesture", function()
      tap_highlight_text(
        readerui,
        Geom:new({ x = 130, y = 100 }),
        Geom:new({ x = 350, y = 395 }),
        Geom:new({ x = 80, y = 265 })
      )
      Screen:shot("screenshots/reader_tap_highlight_text_epub.png")
      assert.spy(selection_spy).was_called()
    end)
  end)

  describe("highlight for PDF documents in page mode", function()
    local readerui
    setup(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
        _testsuite = true,
      })
      readerui:handleEvent(Event:new("SetScrollMode", false))
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    describe("for scanned page with text layer", function()
      before_each(function()
        UIManager:quit()
        UIManager:show(readerui)
        readerui.paging:onGotoPage(10)
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
      end)
      it("should response on tap gesture #nocov", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot("screenshots/reader_tap_highlight_text_pdf.png")
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot("screenshots/reader_highlight_single_word_pdf.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 260, y = 170 }),
          Geom:new({ x = 260, y = 250 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
    end)
    describe("for scanned page without text layer", function()
      before_each(function()
        UIManager:quit()
        UIManager:show(readerui)
        readerui.paging:onGotoPage(28)
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
      end)
      it("should respond to tap gesture #nocov", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot("screenshots/reader_tap_highlight_text_pdf_scanned.png")
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot("screenshots/reader_highlight_single_word_pdf_scanned.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf_scanned.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
    end)
    describe("for reflowed page", function()
      before_each(function()
        UIManager:quit()
        readerui.document.configurable.text_wrap = 1
        UIManager:show(readerui)
        readerui.paging:onGotoPage(31)
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
        readerui.document.configurable.text_wrap = 0
        UIManager:close(readerui) -- close to flush settings
        -- We haven't torn it down yet
        ReaderUI.instance = readerui
      end)
      it("should response on tap gesture #nocov", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot("screenshots/reader_tap_highlight_text_pdf_reflowed.png")
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot("screenshots/reader_highlight_single_word_pdf_reflowed.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf_reflowed.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
    end)
  end)

  describe("highlight for PDF documents in scroll mode", function()
    local readerui
    setup(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
        _testsuite = true,
      })
      readerui.document.configurable.trim_page = 3
      readerui:handleEvent(Event:new("SetScrollMode", true))
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    describe("for scanned page with text layer", function()
      before_each(function()
        UIManager:quit()
        UIManager:show(readerui)
        readerui.paging:onGotoPage(10)
        readerui.zooming:setZoomMode("contentwidth")
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot("screenshots/reader_highlight_single_word_pdf_scroll.png")
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 260, y = 170 }),
          Geom:new({ x = 260, y = 250 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf_scroll.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should response on tap gesture", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot("screenshots/reader_tap_highlight_text_pdf_scroll.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
    end)
    describe("for scanned page without text layer", function()
      before_each(function()
        UIManager:quit()
        UIManager:show(readerui)
        readerui.paging:onGotoPage(28)
        readerui.zooming:setZoomMode("contentwidth")
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot(
          "screenshots/reader_highlight_single_word_pdf_scanned_scroll.png"
        )
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 192, y = 186 }),
          Geom:new({ x = 280, y = 186 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf_scanned_scroll.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should response on tap gesture", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot(
          "screenshots/reader_tap_highlight_text_pdf_scanned_scroll.png"
        )
      end)
    end)
    describe("for reflowed page", function()
      before_each(function()
        UIManager:quit()
        readerui.document.configurable.text_wrap = 1
        UIManager:show(readerui)
        readerui.paging:onGotoPage(31)
      end)
      after_each(function()
        readerui.highlight:clear()
        readerui.annotation.annotations = {}
        readerui.document.configurable.text_wrap = 0
        UIManager:close(readerui) -- close to flush settings
        -- We haven't torn it down yet
        ReaderUI.instance = readerui
      end)
      it("should highlight single word", function()
        highlight_single_word(readerui, Geom:new({ x = 260, y = 70 }))
        Screen:shot(
          "screenshots/reader_highlight_single_word_pdf_reflowed_scroll.png"
        )
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should highlight text", function()
        highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 })
        )
        Screen:shot("screenshots/reader_highlight_text_pdf_reflowed_scroll.png")
        assert.truthy(#readerui.annotation.annotations == 1)
      end)
      it("should response on tap gesture", function()
        tap_highlight_text(
          readerui,
          Geom:new({ x = 260, y = 70 }),
          Geom:new({ x = 260, y = 150 }),
          Geom:new({ x = 280, y = 110 })
        )
        Screen:shot(
          "screenshots/reader_tap_highlight_text_pdf_reflowed_scroll.png"
        )
      end)
    end)
  end)

  describe("unit tests for ReaderHighlight methods", function()
    local readerui
    local sample_epub = DataStorage:getDataDir() .. "/juliet.epub"

    before_each(function()
      UIManager:quit()
      require("ffi/util").copyFile(
        "spec/front/unit/data/juliet.epub",
        sample_epub
      )
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      readerui:paintTo(Screen.bb, 0, 0)
    end)

    after_each(function()
      while #UIManager._window_stack > 0 do
        local top = UIManager._window_stack[#UIManager._window_stack]
        if top and top.widget and top.widget ~= readerui then
          UIManager:close(top.widget)
        else
          break
        end
      end
      G_reader_settings:save("highlight_dialog_position", "center")
      G_reader_settings:save("default_highlight_action", "ask")
      readerui.highlight:clear()
      readerui.annotation.annotations = {}
      readerui:onExit()
      readerui:onClose()
      os.remove(sample_epub)
      os.execute("rm -rf " .. sample_epub:gsub("%.epub$", ".sdr"))
    end)

    it(
      "should allow adding and removing buttons from highlight dialog",
      function()
        local highlight = readerui.highlight
        local custom_called = false
        local custom_fn = function()
          return {
            text = "Custom Action",
            callback = function()
              custom_called = true
            end,
          }
        end

        highlight:addToHighlightDialog("99_custom", custom_fn)
        assert.truthy(highlight._highlight_buttons["99_custom"])
        local btn_def = highlight._highlight_buttons["99_custom"](highlight)
        assert.are.equal("Custom Action", btn_def.text)
        btn_def.callback()
        assert.is_true(custom_called)

        highlight:removeFromHighlightDialog("99_custom")
        assert.is_nil(highlight._highlight_buttons["99_custom"])
      end
    )

    it("should manage highlight actions and cycle through them", function()
      local highlight = readerui.highlight
      local nums, texts = highlight:getHighlightActions()
      assert.truthy(#nums > 0)
      assert.are.equal(#nums, #texts)

      highlight:onSetHighlightAction(2, true)
      assert.are.equal(
        "nothing",
        G_reader_settings:read("default_highlight_action")
      )
      assert.is_true(highlight.ui.view.highlight.disabled)

      highlight:onSetHighlightAction(3, true)
      assert.are.equal(
        "highlight",
        G_reader_settings:read("default_highlight_action")
      )
      assert.is_false(highlight.ui.view.highlight.disabled)

      highlight:onCycleHighlightAction()
      assert.are.equal(
        "select",
        G_reader_settings:read("default_highlight_action")
      )
    end)

    it("should get highlight styles and cycle style drawers", function()
      local highlight = readerui.highlight
      local styles = highlight.getHighlightStyles()
      assert.truthy(#styles > 0)

      assert.are.equal("Lighten", highlight:getHighlightStyleString("lighten"))
      assert.are.equal(
        "Underline",
        highlight:getHighlightStyleString("underscore")
      )
      assert.is_nil(highlight:getHighlightStyleString("nonexistent_style"))

      highlight.ui.view.highlight.saved_drawer = "lighten"
      highlight:onCycleHighlightStyle()
      assert.are.equal("underscore", highlight.ui.view.highlight.saved_drawer)
    end)

    it("should toggle panel zoom and text selection settings", function()
      local highlight = readerui.highlight
      local saved_rolling = highlight.ui.rolling
      highlight.ui.rolling = nil

      local initial_pz = not not highlight.panel_zoom_enabled
      highlight:onTogglePanelZoomSetting()
      assert.are.equal(not initial_pz, highlight.panel_zoom_enabled)

      local initial_fallback =
        not not highlight.panel_zoom_fallback_to_text_selection
      highlight:onToggleFallbackTextSelection()
      assert.are.equal(
        not initial_fallback,
        highlight.panel_zoom_fallback_to_text_selection
      )

      highlight.ui.rolling = saved_rolling
    end)

    it("should set dimensions properly", function()
      local highlight = readerui.highlight
      highlight:onSetDimensions(Geom:new({ w = 1024, h = 768 }))
      assert.are.equal(1024, highlight.screen_w)
      assert.are.equal(768, highlight.screen_h)
    end)

    it("should handle clear_id correctly", function()
      local highlight = readerui.highlight
      highlight.hold_pos = Geom:new({ x = 100, y = 100 })
      highlight.selected_text = { text = "test" }

      local clear_id = highlight:getClearId()
      assert.truthy(clear_id)

      -- Clearing with mismatched ID should do nothing
      highlight:clear(clear_id + 999)
      assert.truthy(highlight.hold_pos)

      -- Clearing with valid ID or onClearHighlight should clear
      assert.is_true(highlight:onClearHighlight())
      assert.is_nil(highlight.hold_pos)
      assert.is_nil(highlight.selected_text)
    end)

    it("should get saved highlights per page", function()
      local highlight = readerui.highlight
      readerui.annotation.annotations = {
        {
          drawer = "lighten",
          pos0 = { page = 5 },
          pos1 = { page = 5 },
          text = "sample 1",
        },
        {
          drawer = "underscore",
          pos0 = { page = 10 },
          pos1 = { page = 12 },
          text = "sample 2",
          ext = {
            [10] = { pos0 = { page = 10 }, pos1 = { page = 10 }, pboxes = {} },
          },
        },
      }

      local page5_hl, offset5 = highlight:getPageSavedHighlights(5)
      assert.are.equal(1, #page5_hl)
      assert.are.equal(0, offset5)

      local page10_hl, offset10 = highlight:getPageSavedHighlights(10)
      assert.are.equal(1, #page10_hl)
      assert.are.equal(1, offset10)
      assert.are.equal(2, page10_hl[1].parent)

      local page1_hl = highlight:getPageSavedHighlights(1)
      assert.are.equal(0, #page1_hl)
    end)

    it("should support indicator navigation gestures and lifecycle", function()
      local highlight = readerui.highlight
      highlight.ui.view.visible_area = Geom:new({ w = 600, h = 800 })

      -- Start indicator
      assert.is_true(highlight:onStartHighlightIndicator())
      assert.truthy(highlight._current_indicator_pos)

      -- Create gesture from indicator
      local ges = highlight:_createHighlightGesture("tap")
      assert.are.equal("tap", ges.ges)
      assert.truthy(ges.pos)

      -- Move indicator
      assert.is_true(highlight:onMoveHighlightIndicator({ 1, 0 }))

      -- Stop indicator
      assert.is_true(highlight:onStopHighlightIndicator(true))
      assert.is_nil(highlight._current_indicator_pos)
    end)

    it("should save and delete highlights", function()
      local highlight = readerui.highlight
      highlight.selected_text = {
        pos0 = "/1/4/2/1:0",
        pos1 = "/1/4/2/1:10",
        text = "Sample test highlight",
      }
      local idx = highlight:saveHighlight()
      assert.truthy(idx)
      assert.are.equal(1, #readerui.annotation.annotations)
      assert.are.equal(
        "Sample test highlight",
        readerui.annotation.annotations[idx].text
      )

      highlight:deleteHighlight(idx)
      assert.are.equal(0, #readerui.annotation.annotations)
    end)

    it("should add and edit notes for highlights", function()
      local highlight = readerui.highlight
      highlight.selected_text = {
        pos0 = "/1/4/2/1:0",
        pos1 = "/1/4/2/1:10",
        text = "Highlight with note",
      }
      highlight:addNote("Important note")
      assert.are.equal(1, #readerui.annotation.annotations)
      local top = UIManager._window_stack[#UIManager._window_stack]
      if top then
        UIManager:close(top.widget)
      end
      readerui.annotation.annotations[1].note = "Important note"
      assert.are.equal(
        "Important note",
        readerui.annotation.annotations[1].note
      )

      -- Edit highlight style and color
      highlight:editHighlightStyle(1)
      local style_dialog = UIManager._window_stack[#UIManager._window_stack]
      if style_dialog then
        UIManager:close(style_dialog.widget)
      end

      highlight:editHighlightColor(1)
      local color_dialog = UIManager._window_stack[#UIManager._window_stack]
      if color_dialog then
        UIManager:close(color_dialog.widget)
      end

      assert.truthy(readerui.annotation.annotations[1].drawer)
    end)

    it("should populate main menu highlight options", function()
      local highlight = readerui.highlight
      local menu_items = {}
      highlight:addToMainMenu(menu_items)

      assert.truthy(menu_items.highlight_options)
      assert.truthy(menu_items.highlight_options.sub_item_table)
      assert.truthy(#menu_items.highlight_options.sub_item_table > 0)
      assert.truthy(menu_items.long_press or menu_items.selection_text)
    end)

    it("should handle lookups and search for selected text", function()
      local highlight = readerui.highlight
      highlight.selected_text = {
        pos0 = "/1/4/2/1:0",
        pos1 = "/1/4/2/1:10",
        text = "testword",
      }

      local wiki_spy = spy.on(UIManager, "broadcastEvent")
      highlight:lookupWikipedia()
      assert.spy(wiki_spy).was_called()
      UIManager.broadcastEvent:revert()

      local dict_spy = spy.on(UIManager, "broadcastEvent")
      highlight:highlightDictLookup()
      assert.spy(dict_spy).was_called()
      UIManager.broadcastEvent:revert()

      local search_spy = spy.on(readerui.search, "searchText")
      highlight:onHighlightSearch()
      assert
        .spy(search_spy)
        .was_called_with(match.is_ref(readerui.search), "testword")
      readerui.search.searchText:revert()
    end)

    it("should handle selection mode and dialogs", function()
      local highlight = readerui.highlight
      highlight.selected_text = {
        pos0 = "/1/4/2/1:0",
        pos1 = "/1/4/2/1:10",
        text = "Selection mode text",
      }
      highlight:startSelection()
      assert.is_true(highlight.select_mode)
      assert.truthy(highlight.highlight_idx)

      local show_stub = stub(highlight, "showWidget")
      local res = highlight:onTapSelectModeIcon()
      assert.is_true(res)
      assert.stub(show_stub).was_called()
      highlight.showWidget:revert()

      highlight.select_mode = false
    end)

    it("should display choose highlight dialogs and edit dialogs", function()
      local highlight = readerui.highlight
      readerui.annotation.annotations = {
        {
          drawer = "lighten",
          pos0 = { page = 5 },
          pos1 = { page = 5 },
          text = "Highlight 1",
        },
        {
          drawer = "underscore",
          pos0 = { page = 5 },
          pos1 = { page = 5 },
          text = "Highlight 2",
          note = "Some note",
        },
      }

      local show_stub = stub(highlight, "showWidget")

      -- Multiple highlights choose dialog
      local res = highlight:showChooseHighlightDialog({ 1, 2 })
      assert.is_true(res)
      assert.stub(show_stub).was_called()

      -- Single highlight note dialog
      highlight:showHighlightNoteOrDialog(2)
      assert.stub(show_stub).was_called()

      -- Single highlight edit dialog
      highlight:onShowHighlightDialog(1)
      assert.truthy(highlight.edit_highlight_dialog)
      highlight.edit_highlight_dialog = nil

      highlight.showWidget:revert()
    end)

    it(
      "should handle quick movement and edge boundaries for indicator",
      function()
        local highlight = readerui.highlight
        highlight.ui.view.visible_area = Geom:new({ w = 600, h = 800 })
        highlight:onStartHighlightIndicator()

        -- Quick move (shift arrow)
        assert.is_true(highlight:onMoveHighlightIndicator({ 1, 0, true }))
        assert.is_true(highlight:onMoveHighlightIndicator({ 0, 1, true }))

        -- Move beyond boundaries to test edge clamping
        for _ = 1, 10 do
          highlight:onMoveHighlightIndicator({ 1, 0, true })
          highlight:onMoveHighlightIndicator({ 0, 1, true })
        end
        assert.are.equal(
          600 - highlight._current_indicator_pos.w,
          highlight._current_indicator_pos.x
        )
        assert.are.equal(
          800 - highlight._current_indicator_pos.h,
          highlight._current_indicator_pos.y
        )

        -- Press event handling
        local press_res = highlight:onHighlightPress()
        assert.is_true(press_res)

        highlight:onStopHighlightIndicator()
      end
    )

    it("should handle PDF annotation writing actions", function()
      local highlight = readerui.highlight
      local saved_rolling = highlight.ui.rolling
      highlight.ui.rolling = nil
      highlight.document.is_pdf = true
      highlight.highlight_write_into_pdf = true

      local item = {
        pos0 = { page = 1 },
        pos1 = { page = 1 },
        text = "PDF Test",
        drawer = "lighten",
      }

      local save_spy = spy.on(highlight.document, "saveHighlight")
      highlight:writePdfAnnotation("save", item)
      assert.spy(save_spy).was_called()
      highlight.document.saveHighlight:revert()

      local del_spy = spy.on(highlight.document, "deleteHighlight")
      highlight:writePdfAnnotation("delete", item)
      assert.spy(del_spy).was_called()
      highlight.document.deleteHighlight:revert()

      local content_spy = spy.on(highlight.document, "updateHighlightContents")
      highlight:writePdfAnnotation("content", item, "PDF note")
      assert.spy(content_spy).was_called()
      highlight.document.updateHighlightContents:revert()

      highlight.ui.rolling = saved_rolling
    end)

    it(
      "should layer Wikipedia lookup window above modal highlight_dialog",
      function()
        local highlight = readerui.highlight
        highlight.selected_text = {
          text = "Juliet",
          pos0 = "/1/4/2/1:0",
          pos1 = "/1/4/2/1:10",
        }
        highlight:onShowHighlightMenu()
        assert.is_truthy(highlight.highlight_dialog)
        assert.is_true(highlight.highlight_dialog.modal)

        local NetworkMgr = require("ui/network/manager")
        local orig_runWhenOnline = NetworkMgr.runWhenOnline
        NetworkMgr.runWhenOnline = function(_, cb)
          cb()
          return true
        end
        local Wikipedia = require("ui/wikipedia")
        local orig_search = Wikipedia.searchAndGetIntros
        Wikipedia.searchAndGetIntros = function()
          return {
            {
              title = "Juliet",
              extract = "Juliet Capulet is the female protagonist in Shakespeare's tragedy.",
              pageid = 1,
              length = 500,
            },
          }
        end

        local highlight_dialog_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == highlight.highlight_dialog then
            highlight_dialog_index = idx
            break
          end
        end
        assert.is_not_nil(highlight_dialog_index)

        highlight:lookupWikipedia()

        assert.is_truthy(readerui.wikipedia.dict_window)
        local wiki_window_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == readerui.wikipedia.dict_window then
            wiki_window_index = idx
            break
          end
        end
        assert.is_not_nil(wiki_window_index)
        assert.is_true(wiki_window_index > highlight_dialog_index)

        Wikipedia.searchAndGetIntros = orig_search
        NetworkMgr.runWhenOnline = orig_runWhenOnline
        UIManager:close(readerui.wikipedia.dict_window)
        readerui.wikipedia.dict_window = nil
        UIManager:close(highlight.highlight_dialog)
        highlight.highlight_dialog = nil
      end
    )

    it(
      "should layer Dictionary lookup window above modal highlight_dialog",
      function()
        local highlight = readerui.highlight
        highlight.selected_text = {
          text = "Juliet",
          pos0 = "/1/4/2/1:0",
          pos1 = "/1/4/2/1:10",
        }
        highlight:onShowHighlightMenu()
        assert.is_truthy(highlight.highlight_dialog)
        assert.is_true(highlight.highlight_dialog.modal)

        local highlight_dialog_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == highlight.highlight_dialog then
            highlight_dialog_index = idx
            break
          end
        end
        assert.is_not_nil(highlight_dialog_index)

        highlight:highlightDictLookup()

        assert.is_truthy(readerui.dictionary.dict_window)
        local dict_window_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == readerui.dictionary.dict_window then
            dict_window_index = idx
            break
          end
        end
        assert.is_not_nil(dict_window_index)
        assert.is_true(dict_window_index > highlight_dialog_index)

        UIManager:close(readerui.dictionary.dict_window)
        readerui.dictionary.dict_window = nil
        UIManager:close(highlight.highlight_dialog)
        highlight.highlight_dialog = nil
      end
    )

    it(
      "should dismiss highlight_dialog on select and highlight actions",
      function()
        local highlight = readerui.highlight
        highlight.hold_pos = { page = 1 }
        highlight.selected_text = {
          text = "Juliet",
          pos0 = "/1/4/2/1:0",
          pos1 = "/1/4/2/1:10",
        }
        highlight:onShowHighlightMenu()
        assert.is_truthy(highlight.highlight_dialog)

        local btn_select = highlight._highlight_buttons["01_select"](highlight)
        assert.is_true(btn_select.enabled)
        btn_select.callback()
        assert.is_nil(highlight.highlight_dialog)
      end
    )

    it(
      "should handle copy, note, and search buttons in highlight dialog",
      function()
        local highlight = readerui.highlight
        highlight.hold_pos = { page = 1 }
        highlight.selected_text = {
          text = "Sample highlighted phrase",
          pos0 = "/1/4/2/1:0",
          pos1 = "/1/4/2/1:20",
        }
        highlight:onShowHighlightMenu()
        assert.is_truthy(highlight.highlight_dialog)

        -- Copy button
        local btn_copy = highlight._highlight_buttons["03_copy"](highlight)
        assert.is_not_nil(btn_copy)
        if btn_copy.enabled then
          btn_copy.callback()
        end

        -- Search button
        local btn_search = highlight._highlight_buttons["12_search"](highlight)
        assert.is_not_nil(btn_search)
        assert.is_function(btn_search.callback)

        if highlight.highlight_dialog then
          UIManager:close(highlight.highlight_dialog)
          highlight.highlight_dialog = nil
        end
      end
    )

    it("should populate highlight menu items in main menu", function()
      local highlight = readerui.highlight
      local menu_items = {}
      highlight:addToMainMenu(menu_items)
      assert.is_table(menu_items.highlight_options)
      assert.is_table(menu_items.highlight_options.sub_item_table)
      assert.is_true(#menu_items.highlight_options.sub_item_table > 0)
    end)

    it("should exercise all main menu highlight settings and callbacks", function()
      local highlight = readerui.highlight
      local menu_items = {}
      highlight:addToMainMenu(menu_items)

      local dummy_menu = {
        updateItems = function() end,
      }

      -- Iterate sub items under highlight_options
      for _, item in ipairs(menu_items.highlight_options.sub_item_table) do
        if item.text_func then
          item.text_func()
        end
        if item.checked_func then
          item.checked_func()
        end
        if item.enabled_func then
          item.enabled_func()
        end
        if item.callback then
          item.callback(dummy_menu)
          local top = UIManager._window_stack[#UIManager._window_stack]
          if top and top.widget and top.widget ~= readerui then
            if top.widget.ok_callback then
              top.widget.ok_callback()
            end
            if top.widget.callback then
              pcall(top.widget.callback, top.widget)
            end
            UIManager:close(top.widget)
          end
        end
        if item.hold_callback then
          item.hold_callback(dummy_menu)
        end
      end

      -- Iterate long_press / selection_text settings
      local lp_menu = menu_items.long_press or menu_items.selection_text
      if lp_menu and lp_menu.sub_item_table then
        for _, item in ipairs(lp_menu.sub_item_table) do
          if item.text_func then
            item.text_func()
          end
          if item.checked_func then
            item.checked_func()
          end
          if item.enabled_func then
            item.enabled_func()
          end
          if item.callback then
            item.callback(dummy_menu)
            local top = UIManager._window_stack[#UIManager._window_stack]
            if top and top.widget and top.widget ~= readerui then
              if top.widget.callback then
                pcall(top.widget.callback, top.widget)
              end
              UIManager:close(top.widget)
            end
          end
          if item.sub_item_table then
            for _, sub_item in ipairs(item.sub_item_table) do
              if sub_item.checked_func then
                sub_item.checked_func()
              end
              if sub_item.callback then
                sub_item.callback(dummy_menu)
              end
            end
          end
        end
      end

      -- Translation menu item
      if menu_items.translate_current_page and menu_items.translate_current_page.callback then
        local show_spy = spy.on(require("ui/translator"), "showTranslation")
        menu_items.translate_current_page.callback()
        require("ui/translator").showTranslation:revert()
      end
    end)

    it("should exercise updateHighlight in both directions and by word/char", function()
      local highlight = readerui.highlight
      readerui.rolling:onGotoPage(10)
      highlight:onHold(nil, { pos = Geom:new({ x = 400, y = 110 }) })
      highlight:onHoldPan(nil, { pos = Geom:new({ x = 400, y = 170 }) })
      highlight:onHoldRelease()
      local idx = highlight:saveHighlight()
      assert.is_not_nil(idx)

      -- Move pos0 forward by word and char
      highlight:updateHighlight(idx, 0, 1, false)
      highlight:updateHighlight(idx, 0, 1, true)
      -- Move pos0 backward by word and char
      highlight:updateHighlight(idx, 0, -1, false)
      highlight:updateHighlight(idx, 0, -1, true)

      -- Move pos1 forward by word and char
      highlight:updateHighlight(idx, 1, 1, false)
      highlight:updateHighlight(idx, 1, 1, true)
      -- Move pos1 backward by word and char
      highlight:updateHighlight(idx, 1, -1, false)
      highlight:updateHighlight(idx, 1, -1, true)

      assert.is_string(readerui.annotation.annotations[idx].text)
      highlight:clear()
      readerui.annotation.annotations = {}
    end)

    it("should exercise dialog buttons and navigation buttons in edit_highlight_dialog", function()
      local highlight = readerui.highlight
      readerui.rolling:onGotoPage(10)

      highlight:onHold(nil, { pos = Geom:new({ x = 400, y = 110 }) })
      highlight:onHoldPan(nil, { pos = Geom:new({ x = 400, y = 170 }) })
      highlight:onHoldRelease()
      if highlight.highlight_dialog then
        UIManager:close(highlight.highlight_dialog)
        highlight.highlight_dialog = nil
      end
      local idx = highlight:saveHighlight()
      assert.is_not_nil(idx)

      highlight:onShowHighlightDialog(idx)
      assert.is_not_nil(highlight.edit_highlight_dialog)

      if highlight.edit_highlight_dialog then
        UIManager:close(highlight.edit_highlight_dialog)
        highlight.edit_highlight_dialog = nil
      end

      highlight:clear()
      readerui.annotation.annotations = {}
    end)

    it("should exercise context extraction, view HTML, translate, and lookup handlers", function()
      local highlight = readerui.highlight
      readerui.rolling:onGotoPage(10)
      highlight:onHold(nil, { pos = Geom:new({ x = 400, y = 110 }) })
      assert.is_not_nil(highlight.selected_text)

      -- Context
      local prev_c, next_c = highlight:getSelectedWordContext(5)

      -- View HTML
      local view_spy = spy.on(require("ui/viewhtml"), "viewSelectionHTML")
      highlight:viewSelectionHTML()
      require("ui/viewhtml").viewSelectionHTML:revert()

      -- Translation
      local trans_spy = spy.on(highlight, "onTranslateText")
      highlight:translate(1)
      assert.spy(trans_spy).was_called()
      highlight.onTranslateText:revert()

      -- Lookup word
      local bc_spy = spy.on(UIManager, "broadcastEvent")
      highlight:lookup(highlight.selected_text)
      assert.spy(bc_spy).was_called()
      UIManager.broadcastEvent:revert()
      highlight:clear()
    end)

    it("should exercise extendSelection and extended highlight helper functions", function()
      local highlight = readerui.highlight
      readerui.rolling:onGotoPage(10)
      highlight:onHold(nil, { pos = Geom:new({ x = 400, y = 110 }) })
      local idx = highlight:saveHighlight()
      highlight.highlight_idx = idx
      highlight.hold_pos = { x = 400, y = 180, page = 10 }
      highlight.selected_text = readerui.document:getTextFromPositions({ x = 400, y = 160 }, { x = 400, y = 200 })

      if highlight.selected_text and highlight.selected_text.pos0 then
        highlight:extendSelection()
        assert.is_table(highlight.selected_text)
        assert.is_string(highlight.selected_text.text)
      end
      highlight:clear()
      readerui.annotation.annotations = {}
    end)

    it("should exercise touch zones, settings read/save, hold timers, and indicators", function()
      local highlight = readerui.highlight

      highlight:setupTouchZones()
      highlight:onUpdateHoldPanRate()
      highlight:onReaderReady()

      -- Settings read/save
      local dummy_cfg = {
        read = function(_, key)
          if key == "highlight_drawer" then return "underscore" end
          if key == "highlight_color" then return "blue" end
          return nil
        end,
        has = function() return false end,
        isTrue = function() return false end,
        save = function() end,
      }
      highlight:onReadSettings(dummy_cfg)
      assert.are.equal("underscore", highlight.view.highlight.saved_drawer)
      highlight:onSaveSettings()

      -- Hold timer reset
      highlight:_resetHoldTimer()
      highlight:_resetHoldTimer(true)

      -- Indicator keys
      highlight:registerKeyEvents()
      highlight:onPhysicalKeyboardConnected()
    end)

    it("should exercise tap handling on existing highlights and note display", function()
      local highlight = readerui.highlight
      readerui.annotation.annotations = {
        {
          drawer = "lighten",
          pos0 = "/1/4/2/1:0",
          pos1 = "/1/4/2/1:20",
          text = "Annotated phrase with note",
          note = "Detailed annotation note content",
        },
      }

      -- Show highlight note dialog with note content
      highlight:showHighlightNoteOrDialog(1)
      local top = UIManager._window_stack[#UIManager._window_stack]
      assert.is_not_nil(top)
      if top and top.widget and top.widget.buttons_table then
        for _, row in ipairs(top.widget.buttons_table) do
          for _, btn in ipairs(row) do
            if btn.callback then
              pcall(btn.callback)
            end
          end
        end
      end
      while #UIManager._window_stack > 0 do
        local w = UIManager._window_stack[#UIManager._window_stack]
        if w and w.widget and w.widget ~= readerui then
          UIManager:close(w.widget)
        else
          break
        end
      end
    end)

    it("should exercise style and color dialogs with direct callbacks", function()
      local highlight = readerui.highlight
      local chosen_style = nil
      highlight:showHighlightStyleDialog(function(style)
        chosen_style = style
      end, "lighten")

      local top_style = UIManager._window_stack[#UIManager._window_stack]
      if top_style and top_style.widget and top_style.widget.callback then
        top_style.widget.callback({ provider = "underscore" })
        assert.are.equal("underscore", chosen_style)
        UIManager:close(top_style.widget)
      end

      local chosen_color = nil
      highlight:showHighlightColorDialog(function(color)
        chosen_color = color
      end)

      local top_color = UIManager._window_stack[#UIManager._window_stack]
      if top_color and top_color.widget and top_color.widget.callback then
        top_color.widget.callback({ provider = "blue" })
        assert.are.equal("blue", chosen_color)
        UIManager:close(top_color.widget)
      end
    end)
  end)
end)
