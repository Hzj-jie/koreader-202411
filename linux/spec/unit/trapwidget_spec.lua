describe("TrapWidget", function()
  local TrapWidget
  local Device
  local UIManager

  setup(function()
    require("commonrequire")
    TrapWidget = require("ui/widget/trapwidget")
    Device = require("device")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize invisible TrapWidget without text", function()
    local tw = TrapWidget:new({
      text = false,
    })

    assert.is_true(tw.invisible)
    assert.is_true(tw.modal)
    assert.is_nil(tw.frame)
    assert.truthy(tw.dimen)
    assert.truthy(tw.key_events.AnyKeyPressed)
  end)

  it("should initialize visible TrapWidget with short text", function()
    local tw = TrapWidget:new({
      text = "Loading...",
    })

    assert.is_false(tw.invisible)
    assert.truthy(tw.frame)
    assert.truthy(tw[1])
  end)

  it("should initialize visible TrapWidget with long text using TextBoxWidget", function()
    local long_text = string.rep("Very long loading message that will definitely wrap across multiple lines ", 10)
    local tw = TrapWidget:new({
      text = long_text,
    })

    assert.is_false(tw.invisible)
    assert.truthy(tw.frame)
  end)

  it("should handle gesture events on touch device", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return true end

    local tw = TrapWidget:new({
      text = nil,
    })
    assert.truthy(tw.ges_events.TapDismiss)
    assert.truthy(tw.ges_events.HoldDismiss)
    assert.truthy(tw.ges_events.SwipeDismiss)
    assert.truthy(tw.ges_events.PanReleaseDismiss)

    Device.isTouchDevice = orig_is_touch
  end)

  it("should invoke dismiss_callback and closeIfShown on input events", function()
    local dismissed = false
    local closed_widget = nil
    local orig_closeIfShown = UIManager.closeIfShown
    UIManager.closeIfShown = function(self, w)
      closed_widget = w
    end

    local tw = TrapWidget:new({
      dismiss_callback = function()
        dismissed = true
      end,
    })

    local ev = { code = 10 }
    local res = tw:onAnyKeyPressed(nil, ev)
    assert.is_true(res)
    assert.is_true(dismissed)
    assert.are.equal(tw, closed_widget)

    dismissed = false
    tw:onTapDismiss(nil, ev)
    assert.is_true(dismissed)

    dismissed = false
    tw:onHoldDismiss(nil, ev)
    assert.is_true(dismissed)

    dismissed = false
    tw:onSwipeDismiss(nil, ev)
    assert.is_true(dismissed)

    dismissed = false
    tw:onPanReleaseDismiss(nil, ev)
    assert.is_true(dismissed)

    UIManager.closeIfShown = orig_closeIfShown
  end)

  it("should resend event via nextTick when resend_event is true", function()
    local scheduled_tick = nil
    local orig_nextTick = UIManager.nextTick
    UIManager.nextTick = function(self, func)
      scheduled_tick = func
    end

    local handled_event = nil
    local orig_handleInputEvent = UIManager.handleInputEvent
    UIManager.handleInputEvent = function(self, ev)
      handled_event = ev
    end

    local tw = TrapWidget:new({
      resend_event = true,
    })

    local mock_ev = { key = "Escape" }
    tw:onAnyKeyPressed(nil, mock_ev)

    assert.truthy(scheduled_tick)
    scheduled_tick()
    assert.truthy(handled_event)
    assert.are.equal("onKeyPress", handled_event.handler)
    assert.are.same(mock_ev, handled_event.args[1])

    UIManager.nextTick = orig_nextTick
    UIManager.handleInputEvent = orig_handleInputEvent
  end)

  it("should mark dirty on show and close when frame is present", function()
    local tw = TrapWidget:new({
      text = "Loading frame",
    })

    local dirty_widget = nil
    local dirty_func = nil
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, func)
      dirty_widget = widget
      dirty_func = func
    end

    tw:onShow()
    assert.are.equal(tw, dirty_widget)
    local mode, region = dirty_func()
    assert.are.equal("ui", mode)
    assert.are.equal(tw.frame.dimen, region)

    dirty_widget = "placeholder"
    tw:onClose()
    assert.is_nil(dirty_widget)
    mode, region = dirty_func()
    assert.are.equal("ui", mode)

    -- Without frame:
    local tw_no_frame = TrapWidget:new({ text = false })
    dirty_widget = nil
    tw_no_frame:onShow()
    assert.is_nil(dirty_widget)
    tw_no_frame:onClose()
    assert.is_nil(dirty_widget)

    UIManager.setDirty = orig_setDirty
  end)
end)
