describe("InputDialog widget", function()
  local InputDialog
  setup(function()
    require("commonrequire")
    InputDialog = require("ui/widget/inputdialog")
  end)

  it(
    "should not crash when initialized with empty buttons table and save_callback",
    function()
      local dialog
      assert.has_no.errors(function()
        dialog = InputDialog:new({
          title = "Test",
          save_callback = function() end,
          buttons = {},
        })
      end)
      assert.is_not_nil(dialog)
    end
  )

  it(
    "should not crash when initialized with empty buttons table and add_scroll_buttons=true",
    function()
      local dialog
      assert.has_no.errors(function()
        dialog = InputDialog:new({
          title = "Test",
          add_scroll_buttons = true,
          buttons = {},
        })
      end)
      assert.is_not_nil(dialog)
    end
  )

  it("should set and get input text correctly", function()
    local dialog = InputDialog:new({
      title = "Test",
      input = "initial text",
    })

    assert.is.same("initial text", dialog:getInputText())

    dialog:setInputText("new text")
    assert.is.same("new text", dialog:getInputText())
  end)
  it("should preserve moved offset across recreation", function()
    local UIManager = require("ui/uimanager")
    local dialog = InputDialog:new({
      title = "Test Movable",
      input = "text",
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    assert.truthy(dialog.movable)
    local initial_offset = dialog.movable:getMovedOffset()
    assert.is.same(0, initial_offset.x)
    assert.is.same(0, initial_offset.y)

    -- Move it
    dialog.movable:_moveBy(50, 100)
    local moved_offset = dialog.movable:getMovedOffset()
    assert.is.same(50, moved_offset.x)
    assert.is.same(100, moved_offset.y)

    -- Recreate (simulating keyboard height change or rotation)
    dialog:onKeyboardHeightChanged()

    -- Verify it is recreated and offset is preserved
    local new_offset = dialog.movable:getMovedOffset()
    assert.is.same(50, new_offset.x)
    assert.is.same(100, new_offset.y)

    UIManager:close(dialog)
  end)
  it("should resize container on SetDimensions event", function()
    local UIManager = require("ui/uimanager")
    local Screen = require("device").screen
    local Event = require("ui/event")
    local Geom = require("ui/geometry")

    local dialog = InputDialog:new({
      title = "Test Resize",
      input = "text",
    })

    UIManager:show(dialog)
    UIManager:forceRepaint()

    local old_width = dialog:getSize().w

    -- Simulate screen rotation (change screen size)
    local old_screen_w = Screen:getWidth()
    local old_screen_h = Screen:getHeight()
    -- Mock Screen size methods
    local original_getWidth = Screen.getWidth
    local original_getHeight = Screen.getHeight
    Screen.getWidth = function()
      return old_screen_h
    end
    Screen.getHeight = function()
      return old_screen_w
    end

    -- Broadcast SetDimensions
    UIManager:broadcastEvent(
      Event:new(
        "SetDimensions",
        Geom:new({ w = old_screen_h, h = old_screen_w })
      )
    )
    UIManager:forceRepaint()

    -- Check if dialog container width changed to match new screen width
    local new_width = dialog:getSize().w
    assert.is_not.same(old_width, new_width)
    assert.is.same(old_screen_h, new_width) -- new screen width is old screen height

    -- Restore Screen mock
    Screen.getWidth = original_getWidth
    Screen.getHeight = original_getHeight

    UIManager:close(dialog)
  end)

  describe("disable_auto_keyboard configuration", function()
    it(
      "should set disable_auto_keyboard=true on InputText when add_nav_bar=true",
      function()
        local dialog = InputDialog:new({
          title = "Test Nav Bar",
          input = "",
          add_nav_bar = true,
          fullscreen = true,
        })
        assert.truthy(dialog._input_widget.disable_auto_keyboard)
      end
    )

    it(
      "should set disable_auto_keyboard=false on InputText when add_nav_bar=false/nil",
      function()
        local dialog = InputDialog:new({
          title = "Test No Nav Bar",
          input = "",
        })
        assert.falsy(dialog._input_widget.disable_auto_keyboard)
      end
    )

    it(
      "should not show keyboard on onTapTextBox when disable_auto_keyboard=true",
      function()
        local dialog = InputDialog:new({
          title = "Test Nav Bar",
          input = "",
          add_nav_bar = true,
          fullscreen = true,
        })

        local input_widget = dialog._input_widget
        local show_keyboard_called = false
        input_widget.showKeyboard = function()
          show_keyboard_called = true
        end

        input_widget:onTapTextBox(nil, {})
        assert.falsy(show_keyboard_called)
      end
    )

    it(
      "should show keyboard on onTapTextBox when disable_auto_keyboard=false",
      function()
        local dialog = InputDialog:new({
          title = "Test No Nav Bar",
          input = "",
        })

        local input_widget = dialog._input_widget
        local show_keyboard_called = false
        input_widget.showKeyboard = function()
          show_keyboard_called = true
        end

        input_widget:onTapTextBox(nil, {})
        assert.truthy(show_keyboard_called)
      end
    )
  end)

  it(
    "should close keyboard on tap outside by default, but not if onTap is overridden",
    function()
      local UIManager = require("ui/uimanager")
      local Geom = require("ui/geometry")

      -- Case 1: Default (should close)
      local dialog_default = InputDialog:new({
        title = "Test Default onTap",
        input = "",
        fullscreen = true,
      })
      UIManager:show(dialog_default)
      UIManager:forceRepaint()
      assert.is_true(dialog_default:isKeyboardVisible())

      -- Tap outside (0,0 is outside the keyboard which is at the bottom)
      dialog_default:onTap(nil, { pos = Geom:new({ x = 0, y = 0 }) })
      UIManager:forceRepaint()
      assert.falsy(dialog_default:isKeyboardVisible())
      UIManager:close(dialog_default)

      -- Case 2: Overridden (should NOT close)
      local dialog_override = InputDialog:new({
        title = "Test Override onTap",
        input = "",
        fullscreen = true,
        onTap = function()
          return true
        end,
      })
      UIManager:show(dialog_override)
      UIManager:forceRepaint()
      assert.is_true(dialog_override:isKeyboardVisible())

      dialog_override:onTap(nil, { pos = Geom:new({ x = 0, y = 0 }) })
      UIManager:forceRepaint()
      assert.is_true(dialog_override:isKeyboardVisible()) -- Still visible!
      UIManager:close(dialog_override)
    end
  )

  it("handles number input, getInputValue, and button enablement", function()
    local dialog = InputDialog:new({
      title = "Number Test",
      input = "42",
      input_type = "number",
    })

    assert.are.equal(42, dialog:getInputValue())

    -- Test button enable / disable
    local btn = dialog:button("close")
    if btn then
      dialog:disableButton("close")
      assert.is_false(btn.enabled)
      dialog:enableButton("close")
      assert.is_true(btn.enabled)
    end
  end)

  it(
    "handles addWidget, addTextToInput, editable checks, and keyboard toggles",
    function()
      local UIManager = require("ui/uimanager")
      local Widget = require("ui/widget/widget")
      local dialog = InputDialog:new({
        title = "Widget Test",
        input = "initial",
        add_scroll_buttons = true,
      })

      -- addWidget
      local dummy_w =
        Widget:new({ dimen = require("ui/geometry"):new({ w = 10, h = 10 }) })
      dialog:addWidget(dummy_w)

      -- text ops
      dialog:addTextToInput(" extra")
      assert.is_true(dialog:isTextEditable())
      assert.is_true(dialog:isTextEdited())

      -- Toggle keyboard
      dialog:closeKeyboard()
      assert.is_falsy(dialog:isKeyboardVisible())
      dialog:showKeyboard()
      assert.is_true(dialog:isKeyboardVisible())

      dialog:closeKeyboard()
      assert.is_falsy(dialog:isKeyboardVisible())
      assert.is_nil(dialog.onExit)
      dialog:onCloseDialog()
    end
  )

  it(
    "handles save_callback, reset_callback, and close_callback button interactions",
    function()
      local UIManager = require("ui/uimanager")
      local saved_text, reset_called, closed_mode

      local dialog = InputDialog:new({
        title = "Editor",
        input = "initial text",
        save_callback = function(content, closing)
          saved_text = content
          return true
        end,
        reset_callback = function()
          reset_called = true
          return "original text"
        end,
        close_callback = function(saved)
          closed_mode = saved
        end,
      })

      dialog.showWidget = function(self, w) end

      -- Modify text
      dialog._text_modified = true
      dialog:setInputText("modified text")

      -- Test reset button callback
      local reset_btn = dialog:button("reset")
      assert.is_not_nil(reset_btn)
      reset_btn.callback()
      assert.is_true(reset_called)
      assert.are.equal("original text", dialog:getInputText())

      -- Test save button callback
      dialog._text_modified = true
      local save_btn = dialog:button("save")
      assert.is_not_nil(save_btn)
      save_btn.callback()
      assert.are.equal("original text", saved_text)

      -- Test close button without modified text
      dialog._text_modified = false
      local close_btn = dialog:button("close")
      assert.is_not_nil(close_btn)
      close_btn.callback()
    end
  )

  it(
    "default enter_callback does not invoke callback when default button is disabled",
    function()
      local called = false
      local dialog = InputDialog:new({
        title = "Enter Callback Test",
        buttons = {
          {
            {
              text = "Save",
              id = "save",
              is_enter_default = true,
              enabled = false,
              callback = function()
                called = true
              end,
            },
          },
        },
      })

      dialog.enter_callback()
      assert.is_false(called)

      dialog:enableButton("save")
      dialog.enter_callback()
      assert.is_true(called)

      called = false
      dialog:disableButton("save")
      dialog.enter_callback()
      assert.is_false(called)
    end
  )

  it(
    "does not expose onExit and saves view position on close without closing keyboard or unfocusing",
    function()
      local UIManager = require("ui/uimanager")
      local dialog = InputDialog:new({
        title = "Close Test",
        input = "abc",
      })
      local close_kb_calls = 0
      local unfocus_calls = 0
      local save_pos_calls = 0
      local orig_close_kb = dialog.closeKeyboard
      local orig_unfocus = dialog._input_widget.unfocus
      local orig_save_pos = dialog._saveViewPos
      dialog.closeKeyboard = function(self)
        close_kb_calls = close_kb_calls + 1
        return orig_close_kb(self)
      end
      dialog._input_widget.unfocus = function(self)
        unfocus_calls = unfocus_calls + 1
        return orig_unfocus(self)
      end
      dialog._saveViewPos = function(self)
        save_pos_calls = save_pos_calls + 1
        return orig_save_pos(self)
      end

      finally(function()
        UIManager:closeIfShown(dialog)
      end)

      assert.is_nil(dialog.onExit)
      UIManager:show(dialog)
      UIManager:close(dialog)

      assert.are.equal(1, save_pos_calls)
      assert.are.equal(0, close_kb_calls)
      assert.are.equal(0, unfocus_calls)
    end
  )

  it(
    "passes NOT_FOCUS and NOT_UNFOCUS to refocusWidget without broadcasting Unfocus on init",
    function()
      local bit = require("bit")
      local UIManager = require("ui/uimanager")
      local FocusManager = require("ui/widget/focusmanager")
      local InputText = require("ui/widget/inputtext")

      local orig_refocus = InputDialog.refocusWidget
      local orig_broadcast = UIManager.broadcastEvent
      local orig_unfocus = InputText.unfocus
      local refocus_args
      local unfocus_broadcasts = 0
      local input_unfocus_calls = 0

      InputDialog.refocusWidget = function(self, render_mode, focus_flag)
        refocus_args = { render_mode, focus_flag }
        return orig_refocus(self, render_mode, focus_flag)
      end
      UIManager.broadcastEvent = function(self, event)
        if type(event) == "table" and event.name == "Unfocus" then
          unfocus_broadcasts = unfocus_broadcasts + 1
        elseif event == "Unfocus" then
          unfocus_broadcasts = unfocus_broadcasts + 1
        end
        return orig_broadcast(self, event)
      end
      InputText.unfocus = function(self)
        input_unfocus_calls = input_unfocus_calls + 1
        return orig_unfocus(self)
      end

      local dialog
      finally(function()
        InputDialog.refocusWidget = orig_refocus
        UIManager.broadcastEvent = orig_broadcast
        InputText.unfocus = orig_unfocus
        if dialog then
          UIManager:closeIfShown(dialog)
        end
      end)

      dialog = InputDialog:new({
        title = "Init Focus",
        input = "line1\nline2",
      })

      assert.are.same({
        FocusManager.RENDER_NOW,
        bit.bor(FocusManager.NOT_FOCUS, FocusManager.NOT_UNFOCUS),
      }, refocus_args)
      assert.are.equal(0, unfocus_broadcasts)
      assert.are.equal(0, input_unfocus_calls)
    end
  )

  it(
    "handles reinit and onKeyboardClosed without unfocusing old inputs",
    function()
      local UIManager = require("ui/uimanager")
      local orig_save_pos = InputDialog._saveViewPos
      local save_pos_calls = 0
      InputDialog._saveViewPos = function(self)
        save_pos_calls = save_pos_calls + 1
        return orig_save_pos(self)
      end

      local dialogs = {}
      finally(function()
        InputDialog._saveViewPos = orig_save_pos
        for _, dlg in ipairs(dialogs) do
          if dlg:isKeyboardVisible() then
            dlg:closeKeyboard()
          end
          UIManager:closeIfShown(dlg)
        end
      end)

      for _, opts in ipairs({
        { add_nav_bar = true, fullscreen = true },
        { fullscreen = true },
      }) do
        local dlg = InputDialog:new({
          title = "Kbd Closed",
          input = "text",
          add_nav_bar = opts.add_nav_bar,
          fullscreen = opts.fullscreen,
        })
        table.insert(dialogs, dlg)
        UIManager:show(dlg)
        dlg:showKeyboard()
        assert.is_true(dlg:isKeyboardVisible())

        local old_input = dlg._input_widget
        local old_unfocus_calls = 0
        local orig_old_unfocus = old_input.unfocus
        old_input.unfocus = function(self)
          old_unfocus_calls = old_unfocus_calls + 1
          return orig_old_unfocus(self)
        end

        local prev_save_calls = save_pos_calls
        dlg:onKeyboardClosed()
        assert.is_falsy(dlg:isKeyboardVisible())
        assert.are.equal(0, old_unfocus_calls)
        assert.is_true(save_pos_calls > prev_save_calls)

        local reinit_save_calls = save_pos_calls
        dlg:reinit()
        assert.is_true(save_pos_calls > reinit_save_calls)

        UIManager:close(dlg)
      end
    end
  )

  it(
    "refreshes buttons via refreshButtons in add_nav_bar strike_callback",
    function()
      local dialog = InputDialog:new({
        title = "Scroll",
        add_nav_bar = true,
        fullscreen = true,
      })

      local refresh_buttons_calls = 0
      local go_refresh_calls = 0
      local orig_refresh_buttons = dialog.refreshButtons
      local orig_go_refresh = dialog.go_button.refresh
      dialog.refreshButtons = function(self)
        refresh_buttons_calls = refresh_buttons_calls + 1
        return orig_refresh_buttons(self)
      end
      dialog.go_button.refresh = function(self)
        go_refresh_calls = go_refresh_calls + 1
        return orig_go_refresh(self)
      end

      dialog.curr_line_num = -1
      dialog.strike_callback()
      assert.are.equal(1, refresh_buttons_calls)
      assert.are.equal(0, go_refresh_calls)
    end
  )
end)
