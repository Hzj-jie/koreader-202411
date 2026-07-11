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
end)
