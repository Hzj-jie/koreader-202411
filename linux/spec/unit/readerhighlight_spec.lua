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
      assert.is_true(highlight.view.highlight.disabled)

      highlight:onSetHighlightAction(3, true)
      assert.are.equal(
        "highlight",
        G_reader_settings:read("default_highlight_action")
      )
      assert.is_false(highlight.view.highlight.disabled)

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

      highlight.view.highlight.saved_drawer = "lighten"
      highlight:onCycleHighlightStyle()
      assert.are.equal("underscore", highlight.view.highlight.saved_drawer)
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
      highlight.view.visible_area = Geom:new({ w = 600, h = 800 })

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
  end)
end)
