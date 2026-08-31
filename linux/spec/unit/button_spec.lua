describe("Button widget", function()
  local Button, Blitbuffer, Geom, Size, UIManager

  setup(function()
    require("commonrequire")
    Button = require("ui/widget/button")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
    Size = require("ui/size")
    UIManager = require("ui/uimanager")
  end)

  it(
    "should update label widget color when disabled without dimming after being disabled",
    function()
      local b = Button:new({
        text = "Very long text that will force TextBoxWidget",
        width = 50,
        height = 30,
        avoid_text_truncation = true,
      })

      -- Verify it is indeed a TextBoxWidget (has update method)
      assert.is_not_nil(b.label_widget.update)

      -- Start enabled (color should be black)
      assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_BLACK)

      -- Disable it (should become gray)
      b:disable()
      assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_DARK_GRAY)

      -- Spy on update
      local spy_update = spy.on(b.label_widget, "update")

      -- Disable without dimming (should become black again)
      b:disableWithoutDimming()
      assert.are.equal(b.label_widget.fgcolor, Blitbuffer.COLOR_BLACK)

      assert.spy(spy_update).was_called()
    end
  )

  it("should allow changing from text to icon and vice versa", function()
    local b = Button:new({
      text = "Click me",
    })

    assert.is_equal("Click me", b.text)
    assert.is_nil(b.icon)
    assert.is_equal("Click me", b.label_widget.text)

    -- Change to icon
    b:setIcon("home")
    assert.is_nil(b.text)
    assert.is_equal("home", b.icon)
    assert.is_equal("home", b.label_widget.icon)

    -- Change back to text
    b:setText("Back to text")
    assert.is_equal("Back to text", b.text)
    assert.is_nil(b.icon)
    assert.is_equal("Back to text", b.label_widget.text)
  end)

  it("should initialize Button with text_func, shortcut, and alignment", function()
    local b_text_func = Button:new({
      text_func = function()
        return "Dynamic Text"
      end,
      align = "left",
      preselect = true,
      shortcut = "D",
    })

    assert.are.equal("Dynamic Text", b_text_func.text)
    assert.is_true(b_text_func.frame.invert)
    assert.is_not_nil(b_text_func.key_events.TapSelectButton)
  end)

  it("should initialize Button with call_hold_input_on_tap", function()
    local b = Button:new({
      text = "HoldTap",
      hold_input = "HoldCommand",
      call_hold_input_on_tap = true,
    })
    assert.are.equal("HoldCommand", b.tap_input)
  end)

  it("should handle checked_func and checkmark display text", function()
    local is_checked = false
    local b = Button:new({
      text = "Option",
      checked_func = function()
        return is_checked
      end,
      width = 200,
    })

    assert.are.equal("Option", b:getDisplayText())
    assert.is_not_nil(b:getMinNeededWidth())

    is_checked = true
    assert.are.equal("Option" .. b.checkmark, b:getDisplayText())
  end)

  it("should handle setText preserving frame when width is identical and no truncation tweaks", function()
    local b = Button:new({
      text = "Initial",
      width = 150,
      avoid_text_truncation = false,
    })
    local old_frame = b.frame
    b:setText("Updated", 150)
    assert.are.equal("Updated", b.text)
    assert.are.equal(old_frame, b.frame)
  end)

  it("should handle onFocus and onUnfocus unless no_focus is set", function()
    local b = Button:new({
      text = "Focusable",
    })
    assert.is_nil(b.frame.invert)

    assert.is_true(b:onFocus())
    assert.is_true(b.frame.invert)

    assert.is_true(b:onUnfocus())
    assert.is_false(b.frame.invert)

    local b_no_focus = Button:new({
      text = "NoFocus",
      no_focus = true,
    })
    assert.is_nil(b_no_focus:onFocus())
    assert.is_nil(b_no_focus:onUnfocus())
  end)

  it("should handle enable, disable, enableDisable, and paintTo with enabled_func", function()
    local b = Button:new({
      text = "ToggleEnabled",
    })
    assert.is_true(b.enabled)
    assert.is_false(b:enable()) -- already enabled

    assert.is_true(b:disable())
    assert.is_false(b.enabled)
    assert.is_false(b:disable()) -- already disabled

    b:enableDisable(true)
    assert.is_true(b.enabled)

    b:enableDisable(false)
    assert.is_false(b.enabled)

    -- Test icon button enable/disable
    local b_icon = Button:new({
      icon = "star",
    })
    b_icon:disable()
    assert.is_true(b_icon.label_widget.dim)
    b_icon:enable()
    assert.is_false(b_icon.label_widget.dim)

    -- Test enabled_func during paintTo
    local active = false
    b.enabled_func = function()
      return active
    end
    local bb = Blitbuffer.new(100, 50)
    b:paintTo(bb, 0, 0)
    assert.is_false(b.enabled)

    active = true
    b:paintTo(bb, 0, 0)
    assert.is_true(b.enabled)
  end)

  it("should handle show, hide, and showHide for icon buttons", function()
    local b_icon = Button:new({
      icon = "back",
    })
    assert.is_false(b_icon.hidden)

    b_icon:hide()
    assert.is_true(b_icon.hidden)
    assert.is_true(b_icon.label_widget.hide)

    b_icon:show()
    assert.is_false(b_icon.hidden)
    assert.is_false(b_icon.label_widget.hide)

    b_icon:showHide(false)
    assert.is_true(b_icon.hidden)
    b_icon:showHide(true)
    assert.is_false(b_icon.hidden)
  end)

  it("should handle onTapSelectButton with callback, feedback highlight, and checked_func", function()
    local clicked = false
    local is_checked = false
    local b = Button:new({
      text = "ClickTest",
      callback = function()
        clicked = true
        is_checked = true
      end,
      checked_func = function()
        return is_checked
      end,
    })
    b[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 40 })

    local res = b:onTapSelectButton()
    assert.is_true(res)
    assert.is_true(clicked)

    -- Test with explicit radius
    local b_radius = Button:new({
      text = "RadiusBtn",
      radius = Size.radius.button,
      callback = function() end,
    })
    b_radius[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 40 })
    assert.is_true(b_radius:onTapSelectButton())

    -- Test with icon button
    local b_icon = Button:new({
      icon = "folder",
      callback = function() end,
    })
    b_icon[1].dimen = Geom:new({ x = 0, y = 0, w = 40, h = 40 })
    assert.is_true(b_icon:onTapSelectButton())
  end)

  it("should handle onTapSelectButton with tap_input and tap_input_func", function()
    local input_received = nil
    local b_input = Button:new({
      text = "InputBtn",
      tap_input = "SampleInput",
    })
    b_input.onInput = function(self, input)
      input_received = input
    end
    assert.is_true(b_input:onTapSelectButton())
    assert.are.equal("SampleInput", input_received)

    local b_func = Button:new({
      text = "InputFuncBtn",
      tap_input_func = function()
        return "FuncInput"
      end,
    })
    b_func.onInput = function(self, input)
      input_received = input
    end
    assert.is_true(b_func:onTapSelectButton())
    assert.are.equal("FuncInput", input_received)
  end)

  it("should handle allow_tap_when_disabled and readonly", function()
    local tapped = false
    local b_disabled = Button:new({
      text = "DisabledBtn",
      enabled = false,
      callback = function()
        tapped = true
      end,
    })
    b_disabled[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 40 })
    b_disabled:onTapSelectButton()
    assert.is_false(tapped)

    b_disabled.allow_tap_when_disabled = true
    b_disabled:onTapSelectButton()
    assert.is_true(tapped)

    local b_readonly = Button:new({
      text = "ReadonlyBtn",
      readonly = true,
      callback = function() end,
    })
    b_readonly[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 40 })
    assert.is_nil(b_readonly:onTapSelectButton())
  end)

  it("should handle onHoldSelectButton and onHoldReleaseSelectButton", function()
    local held = false
    local b_hold = Button:new({
      text = "HoldBtn",
      hold_callback = function()
        held = true
      end,
    })

    assert.is_true(b_hold:onHoldSelectButton())
    assert.is_true(held)
    assert.is_true(b_hold:onHoldReleaseSelectButton())
    assert.is_false(b_hold:onHoldReleaseSelectButton()) -- second time false

    -- Test hold_input
    local input_held = nil
    local b_input = Button:new({
      text = "HoldInput",
      hold_input = "HoldCmd",
    })
    b_input.onInput = function(self, input, is_hold)
      input_held = input
    end
    assert.is_true(b_input:onHoldSelectButton())
    assert.are.equal("HoldCmd", input_held)

    -- Test hold_input_func
    local b_func = Button:new({
      text = "HoldFunc",
      hold_input_func = function()
        return "FuncCmd"
      end,
    })
    b_func.onInput = function(self, input, is_hold)
      input_held = input
    end
    assert.is_true(b_func:onHoldSelectButton())
    assert.are.equal("FuncCmd", input_held)
  end)

  it("should handle refresh method", function()
    local b = Button:new({
      text = "Refreshable",
    })
    -- unpainted button
    assert.has_no.errors(function()
      b:refresh()
    end)

    -- painted button
    b[1].dimen = Geom:new({ x = 0, y = 0, w = 100, h = 40 })
    local dirty_widget, dirty_mode
    local old_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, w, mode)
      dirty_widget = w
      dirty_mode = mode
    end

    b:refresh()
    assert.are.equal(b[1], dirty_widget)
    assert.are.equal("fast", dirty_mode)

    b:disable()
    b:refresh()
    assert.are.equal("ui", dirty_mode)

    UIManager.setDirty = old_setDirty
  end)
end)
