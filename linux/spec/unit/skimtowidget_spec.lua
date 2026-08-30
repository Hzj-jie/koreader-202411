describe("SkimToWidget widget", function()
  local SkimToWidget
  local UIManager
  local Event
  local Geom
  local Device
  local mock_ui
  local broadcasted_events

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    Event = require("ui/event")
    Geom = require("ui/geometry")
    Device = require("device")
    SkimToWidget = require("ui/widget/skimtowidget")
  end)

  before_each(function()
    broadcasted_events = {}
    UIManager.broadcastEvent = function(_, event)
      table.insert(broadcasted_events, event)
    end
    UIManager.close = function(_, widget)
      if widget and widget.onClose then
        widget:onClose()
      end
    end
    UIManager.setDirty = function() end

    G_reader_settings:save("skim_dialog_position", nil)

    local current_page = 10
    local added_to_stack = false
    local exited_skim = false
    local entered_skim = false

    mock_ui = {
      getCurrentPage = function()
        return current_page
      end,
      document = {
        getPageCount = function()
          return 100
        end,
        flows = {},
      },
      toc = {
        getTocTicksFlattened = function()
          return { 1, 25, 50, 75, 100 }
        end,
        getNextChapter = function(_, page)
          if page < 25 then
            return 25
          elseif page < 50 then
            return 50
          elseif page < 75 then
            return 75
          else
            return 100
          end
        end,
        getPreviousChapter = function(_, page)
          if page > 75 then
            return 75
          elseif page > 50 then
            return 50
          elseif page > 25 then
            return 25
          else
            return 1
          end
        end,
      },
      pagemap = {
        wantsPageLabels = function()
          return false
        end,
        getCurrentPageLabel = function()
          return "Page X"
        end,
      },
      link = {
        addCurrentLocationToStack = function()
          added_to_stack = true
        end,
        onGoBackLink = function()
          current_page = 5
        end,
      },
      view = {
        dogear_visible = false,
      },
      paging = {
        enterSkimMode = function()
          entered_skim = true
        end,
        exitSkimMode = function()
          exited_skim = true
        end,
      },
      _state = {
        get_added_to_stack = function()
          return added_to_stack
        end,
        get_exited_skim = function()
          return exited_skim
        end,
        get_entered_skim = function()
          return entered_skim
        end,
        set_current_page = function(p)
          current_page = p
        end,
      },
    }
  end)

  it("should initialize SkimToWidget in full mode", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
    assert.are.equal(10, widget.curr_page)
    assert.are.equal(100, widget.page_count)
    assert.is_true(mock_ui._state.get_entered_skim())
    assert.is_table(widget.progress_bar)
    assert.is_table(widget.current_page_text)
    assert.is_table(widget.button_bookmark_toggle)
  end)

  it("should initialize SkimToWidget in compact top mode", function()
    G_reader_settings:save("skim_dialog_position", "top")
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
    assert.are.equal(10, widget.curr_page)
  end)

  it("should initialize SkimToWidget in compact bottom mode", function()
    G_reader_settings:save("skim_dialog_position", "bottom")
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
    assert.are.equal(10, widget.curr_page)
  end)

  it(
    "should setup DPad layout and Keyboard key_events if device supports them",
    function()
      local orig_hasDPad = Device.hasDPad
      local orig_hasKeyboard = Device.hasKeyboard
      Device.hasDPad = function()
        return true
      end
      Device.hasKeyboard = function()
        return true
      end

      -- Test full mode DPad layout and keyboard shortcuts
      G_reader_settings:save("skim_dialog_position", nil)
      local widget_full = SkimToWidget:new({ ui = mock_ui })
      assert.is_table(widget_full.layout)
      assert.are.equal(2, #widget_full.layout)
      assert.is_table(widget_full.key_events.QKey)
      assert.is_table(widget_full.key_events.PKey)

      -- Test compact mode DPad layout
      G_reader_settings:save("skim_dialog_position", "bottom")
      local widget_compact = SkimToWidget:new({ ui = mock_ui })
      assert.is_table(widget_compact.layout)
      assert.are.equal(1, #widget_compact.layout)

      Device.hasDPad = orig_hasDPad
      Device.hasKeyboard = orig_hasKeyboard
    end
  )

  it("should update and clamp page numbers correctly", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget:goToPage(50)
    assert.are.equal(50, widget.curr_page)
    assert.are.equal(50 / 100, widget.progress_bar.percentage)
    assert.is_true(mock_ui._state.get_added_to_stack())
    assert.are.equal(1, #broadcasted_events)
    assert.are.equal("onGotoPage", broadcasted_events[1].handler)
    assert.are.equal(50, broadcasted_events[1].args[1])

    -- Clamp lower bound
    widget:goToPage(-5)
    assert.are.equal(1, widget.curr_page)
    assert.are.equal(1 / 100, widget.progress_bar.percentage)

    -- Clamp upper bound
    widget:goToPage(150)
    assert.are.equal(100, widget.curr_page)
    assert.are.equal(100 / 100, widget.progress_bar.percentage)
  end)

  it("should handle location stack and goToOrigPage", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget:addOriginToLocationStack()
    assert.is_true(widget.orig_page_added_to_stack)
    assert.is_true(mock_ui._state.get_added_to_stack())

    -- Second call should not re-add
    widget:addOriginToLocationStack()
    assert.is_true(widget.orig_page_added_to_stack)

    -- Return to original page
    widget:goToOrigPage()
    assert.is_nil(widget.orig_page_added_to_stack)
    assert.are.equal(5, widget.curr_page)
  end)

  it("should handle key press events for first row key press", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget:onFirstRowKeyPress(0.44)
    assert.are.equal(44, widget.curr_page)

    widget:onFirstRowKeyPress(0)
    assert.are.equal(1, widget.curr_page)

    widget:onFirstRowKeyPress(1)
    assert.are.equal(100, widget.curr_page)
  end)

  it("should handle goToByEvent", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget:goToByEvent("GotoNextBookmarkFromPage")
    assert.is_true(widget.orig_page_added_to_stack)
    assert.are.equal(1, #broadcasted_events)
    assert.are.equal(
      "onGotoNextBookmarkFromPage",
      broadcasted_events[1].handler
    )
    assert.is_false(broadcasted_events[1].args[1])
  end)

  it("should handle tap gestures on progress bar and outside frame", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget.progress_bar.dimen = Geom:new({ x = 10, y = 10, w = 100, h = 20 })
    widget.skimto_frame.dimen = Geom:new({ x = 0, y = 0, w = 200, h = 200 })

    widget.progress_bar.getPercentageFromPosition = function(_, pos)
      if pos:intersectWith(widget.progress_bar.dimen) then
        return 0.6
      end
      return nil
    end

    -- Tap inside progress bar
    local ges_ev_bar = { pos = Geom:new({ x = 50, y = 15 }) }
    local res1 = widget:onTapProgress(nil, ges_ev_bar)
    assert.is_true(res1)
    assert.are.equal(60, widget.curr_page)

    -- Tap outside skimto_frame (should trigger exit)
    local closed = false
    widget.onExit = function()
      closed = true
      return true
    end
    local ges_ev_outside = { pos = Geom:new({ x = 300, y = 300 }) }
    local res2 = widget:onTapProgress(nil, ges_ev_outside)
    assert.is_true(res2)
    assert.is_true(closed)
  end)

  it("should handle navigation button callbacks", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    widget:goToPage(50)

    -- minus 1
    widget:goToPage(widget.curr_page - 1)
    assert.are.equal(49, widget.curr_page)

    -- minus 10
    widget:goToPage(widget.curr_page - 10)
    assert.are.equal(39, widget.curr_page)

    -- plus 1
    widget:goToPage(widget.curr_page + 1)
    assert.are.equal(40, widget.curr_page)

    -- plus 10
    widget:goToPage(widget.curr_page + 10)
    assert.are.equal(50, widget.curr_page)

    -- Chapter prev
    local prev_ch = mock_ui.toc:getPreviousChapter(widget.curr_page)
    widget:goToPage(prev_ch)
    assert.are.equal(25, widget.curr_page)

    -- Chapter next
    local next_ch = mock_ui.toc:getNextChapter(widget.curr_page)
    widget:goToPage(next_ch)
    assert.are.equal(50, widget.curr_page)
  end)

  it(
    "should handle bookmark toggle button callback and hold callback",
    function()
      local widget = SkimToWidget:new({
        ui = mock_ui,
      })

      assert.are.equal("\u{F097}", widget.button_bookmark_toggle:text_func())
      mock_ui.view.dogear_visible = true
      assert.are.equal("\u{F02E}", widget.button_bookmark_toggle:text_func())

      -- Callback
      widget.button_bookmark_toggle:callback()
      assert.are.equal(
        "onToggleBookmark",
        broadcasted_events[#broadcasted_events].handler
      )

      -- Hold callback
      widget.button_bookmark_toggle:hold_callback()
      assert.are.equal(
        "onShowBookmark",
        broadcasted_events[#broadcasted_events].handler
      )
    end
  )

  it("should handle current page text callbacks and labels", function()
    mock_ui.pagemap.wantsPageLabels = function()
      return true
    end
    mock_ui.pagemap.getCurrentPageLabel = function()
      return "iv"
    end

    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    local text = widget.current_page_text:text_func()
    assert.are.equal("iv", text)

    local goto_switched = false
    widget.callback_switch_to_goto = function()
      goto_switched = true
    end
    widget.current_page_text:callback()
    assert.is_true(goto_switched)

    -- Hold callback goes to orig page
    widget:addOriginToLocationStack()
    widget.current_page_text:hold_callback()
    assert.are.equal(5, widget.curr_page)
  end)

  it("should handle show, close, and exit lifecycle methods", function()
    local widget = SkimToWidget:new({
      ui = mock_ui,
    })

    assert.is_true(widget:onShow())

    widget:onClose()
    assert.is_true(mock_ui._state.get_exited_skim())

    local exit_result = widget:onExit()
    assert.is_true(exit_result)
  end)
end)
