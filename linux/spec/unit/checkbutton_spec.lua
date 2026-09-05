describe("CheckButton widget", function()
  local CheckButton
  local UIManager

  setup(function()
    require("commonrequire")
    CheckButton = require("ui/widget/checkbutton")
    UIManager = require("ui/uimanager")
  end)

  local function mockParent(width)
    return {
      getAddedWidgetAvailableWidth = function()
        return width or 200
      end,
    }
  end

  it("should preserve checked state when disabled and re-enabled", function()
    local mock_parent = mockParent(200)

    local original_setDirty = UIManager.setDirty
    UIManager.setDirty = function() end

    local cb = CheckButton:new({
      text = "Test CheckBox",
      checked = true,
      parent = mock_parent,
    })

    assert.is_true(cb.checked)

    -- Disable it
    cb:disable()
    assert.is_true(cb.checked)
    assert.is_false(cb.enabled)

    -- Re-enable it
    cb:enable()
    assert.is_true(cb.checked)
    assert.is_true(cb.enabled)

    UIManager.setDirty = original_setDirty
  end)

  it(
    "should calculate size via getSize and support geometry merge methods",
    function()
      local mock_parent = {
        getAddedWidgetAvailableWidth = function()
          return 200
        end,
      }

      local cb = CheckButton:new({
        text = "Geometry CheckBox",
        parent = mock_parent,
        width = 150,
        height = 40,
      })

      local size = cb:getSize()
      assert.is_not_nil(size)
      assert.is_true(size.w > 0)
      assert.is_true(size.h > 0)

      cb:mergeSize(180, 60)
      local new_size = cb:getSize()
      assert.are.equal(180, new_size.w)
      assert.are.equal(60, new_size.h)
    end
  )

  it("should support mergePosition and dirtyRegion", function()
    local mock_parent = {
      getAddedWidgetAvailableWidth = function()
        return 200
      end,
    }

    local cb = CheckButton:new({
      text = "Position CheckBox",
      parent = mock_parent,
    })

    cb:mergePosition(15, 25)
    local pos_size = cb:getSize()
    assert.are.equal(15, pos_size.x)
    assert.are.equal(25, pos_size.y)

    local region = cb:dirtyRegion()
    assert.is_not_nil(region)
  end)

  it("should support radio mode and custom width", function()
    local cb = CheckButton:new({
      text = "Radio Option",
      radio = true,
      checked = false,
      width = 250,
    })

    assert.is_true(cb.radio)
    assert.is_false(cb.checked)
    assert.are.equal("RadioMark", cb._checkmark.name or cb._checkmark[1] and cb._checkmark[1].name or "RadioMark")
  end)

  it("should handle tap events and toggle checked state", function()
    local callback_called = false
    local cb = CheckButton:new({
      text = "Tap me",
      checked = false,
      parent = mockParent(200),
      callback = function()
        callback_called = true
      end,
    })

    local orig_invert = UIManager.invertWidget
    local orig_forceRepaint = UIManager.forceRepaint
    local orig_waitForScreenRefresh = UIManager.waitForScreenRefresh
    local orig_setDirty = UIManager.setDirty

    UIManager.invertWidget = function() end
    UIManager.forceRepaint = function() end
    UIManager.waitForScreenRefresh = function() end
    UIManager.setDirty = function() end

    local res = cb:onTapCheckButton()
    assert.is_true(res)
    assert.is_true(cb.checked)
    assert.is_true(callback_called)

    -- Tap again to toggle off
    callback_called = false
    cb:onTapCheckButton()
    assert.is_false(cb.checked)
    assert.is_true(callback_called)

    -- When disabled, tap does nothing
    cb.enabled = false
    callback_called = false
    cb:onTapCheckButton()
    assert.is_false(cb.checked)
    assert.is_false(callback_called)

    UIManager.invertWidget = orig_invert
    UIManager.forceRepaint = orig_forceRepaint
    UIManager.waitForScreenRefresh = orig_waitForScreenRefresh
    UIManager.setDirty = orig_setDirty
  end)

  it("should handle tap_input and tap_input_func", function()
    local input_received = nil
    local cb1 = CheckButton:new({
      text = "Input 1",
      parent = mockParent(200),
      tap_input = "CustomTap",
    })
    cb1.onInput = function(self, inp)
      input_received = inp
    end

    cb1:onTapCheckButton()
    assert.are.equal("CustomTap", input_received)

    local cb2 = CheckButton:new({
      text = "Input 2",
      parent = mockParent(200),
      tap_input_func = function()
        return "FuncTap"
      end,
    })
    cb2.onInput = function(self, inp)
      input_received = inp
    end

    cb2:onTapCheckButton()
    assert.are.equal("FuncTap", input_received)
  end)

  it("should handle hold callbacks, hold input, and hold release", function()
    local hold_called = false
    local cb = CheckButton:new({
      text = "Hold me",
      parent = mockParent(200),
      hold_callback = function()
        hold_called = true
      end,
    })

    assert.is_false(cb:onHoldReleaseCheckButton())
    cb:onHoldCheckButton()
    assert.is_true(hold_called)
    assert.is_true(cb:onHoldReleaseCheckButton())

    -- Hold input
    local input_received = nil
    local hold_flag = nil
    local cb_inp = CheckButton:new({
      text = "Hold input",
      parent = mockParent(200),
      hold_input = "HoldInp",
    })
    cb_inp.onInput = function(self, inp, is_hold)
      input_received = inp
      hold_flag = is_hold
    end
    cb_inp:onHoldCheckButton()
    assert.are.equal("HoldInp", input_received)
    assert.is_true(hold_flag)

    -- Hold input func
    local cb_func = CheckButton:new({
      text = "Hold input func",
      parent = mockParent(200),
      hold_input_func = function() return "HoldFunc" end,
    })
    cb_func.onInput = function(self, inp, is_hold)
      input_received = inp
      hold_flag = is_hold
    end
    cb_func:onHoldCheckButton()
    assert.are.equal("HoldFunc", input_received)
    assert.is_true(hold_flag)
  end)

  it("should handle focus and unfocus when enabled and disabled", function()
    local cb = CheckButton:new({
      text = "Focus test",
      parent = mockParent(200),
    })

    assert.is_true(cb:onFocus())
    assert.is_true(cb._frame.invert)

    assert.is_true(cb:onUnfocus())
    assert.is_false(cb._frame.invert)

    cb.enabled = false
    assert.is_false(cb:onFocus())
    assert.is_false(cb:onUnfocus())
  end)

  it("should toggle checked state and invoke setDirty via toggleCheck, enable, and disable", function()
    local dirty_calls = 0
    local cb = CheckButton:new({
      text = "Toggle Test",
      checked = false,
      parent = mockParent(200),
    })
    UIManager:show(cb)

    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, w, f)
      dirty_calls = dirty_calls + 1
      if type(f) == "function" then
        local mode, dimen = f()
        assert.are.equal("ui", mode)
      end
    end

    cb:toggleCheck()
    assert.is_true(cb.checked)
    assert.is_true(dirty_calls >= 1)

    cb:toggleCheck()
    assert.is_false(cb.checked)

    cb:disable()
    assert.is_false(cb.enabled)

    cb:enable()
    assert.is_true(cb.enabled)

    UIManager.setDirty = orig_setDirty
    UIManager:close(cb)
  end)
end)
