describe("ClockWidget plugin module", function()
  local ClockWidget, Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Blitbuffer = require("ffi/blitbuffer")
    ClockWidget = require("plugins/clock.koplugin/clockwidget")
  end)

  it("should initialize clock widget and blitbuffers", function()
    local widget = ClockWidget:new()

    assert.is_table(widget)
    assert.is_table(widget._hands)

    widget:init()
    assert.is_table(widget.face)
  end)

  it("should prepare hand rotations for specified time", function()
    local widget = ClockWidget:new()
    widget:init()

    widget._hours_hand_bb = Blitbuffer.new(20, 20)
    widget._minutes_hand_bb = Blitbuffer.new(20, 20)

    local hands = widget:_prepareHands(10, 15)
    assert.is_table(hands)
    assert.is_table(hands.hours)
    assert.is_table(hands.minutes)

    widget._hours_hand_bb:free()
    widget._minutes_hand_bb:free()
  end)

  it("should paint clock hands onto blitbuffer target", function()
    local widget = ClockWidget:new()
    widget:init()

    widget._hours_hand_bb = Blitbuffer.new(20, 20)
    widget._minutes_hand_bb = Blitbuffer.new(20, 20)

    local canvas = Blitbuffer.new(300, 300)
    widget:paintTo(canvas, 10, 10)
    canvas:free()

    widget._hours_hand_bb:free()
    widget._minutes_hand_bb:free()
  end)

  it("should manage lifecycle events for auto-refresh timers", function()
    local widget = ClockWidget:new()
    widget:init()

    widget:onShow()
    widget:onSuspend()
    widget:onResume()
    widget:onClose()
  end)

  it("should load real hand images and paint clock without error", function()
    local widget = ClockWidget:new()
    widget:init()

    -- Verify that PLUGIN_ROOT successfully resolved and images loaded
    assert.is_not_nil(widget._hours_hand_bb)
    assert.is_not_nil(widget._minutes_hand_bb)
    assert.is_true(widget._hours_hand_bb:getWidth() > 0)
    assert.is_true(widget._minutes_hand_bb:getWidth() > 0)

    -- Verify preparing hands and rotation uses real loaded buffers
    local hands = widget:_prepareHands(10, 15)
    assert.is_table(hands)
    assert.is_table(hands.hours)
    assert.is_table(hands.minutes)

    -- Verify paintTo renders face and hands onto destination canvas
    local canvas = Blitbuffer.new(300, 300)
    assert.has_no.errors(function()
      widget:paintTo(canvas, 10, 10)
    end)
    canvas:free()
  end)
end)
