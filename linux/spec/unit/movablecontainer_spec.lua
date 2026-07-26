describe("MovableContainer widget", function()
  local MovableContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    MovableContainer = require("ui/widget/container/movablecontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize with default parameters", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
    })

    assert.is_table(container)
    local offset = container:getMovedOffset()
    assert.are.equal(0, offset.x)
    assert.are.equal(0, offset.y)
    assert.is_nil(container.alpha)
  end)

  it("should handle setting and resetting moved offset", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
    })

    container:setMovedOffset(Geom:new({ x = 20, y = 30 }))
    local offset = container:getMovedOffset()
    assert.are.equal(20, offset.x)
    assert.are.equal(30, offset.y)

    container:setMovedOffset(Geom:new({ x = 0, y = 0 }))
    offset = container:getMovedOffset()
    assert.are.equal(0, offset.x)
    assert.are.equal(0, offset.y)
  end)

  it("should toggle alpha on hold gesture when unmoved", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }),
    })

    container:onMovableHold(nil, { pos = Geom:new({ x = 15, y = 15 }) })
    container:onMovableHoldRelease(nil, { pos = Geom:new({ x = 15, y = 15 }) })
    assert.are.equal(0.6, container.alpha)

    container:onMovableHold(nil, { pos = Geom:new({ x = 15, y = 15 }) })
    container:onMovableHoldRelease(nil, { pos = Geom:new({ x = 15, y = 15 }) })
    assert.is_nil(container.alpha)
  end)

  it("should handle swipe gestures to move offset within bounds", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }),
    })

    local handled = container:onMovableSwipe(nil, {
      pos = Geom:new({ x = 15, y = 15 }),
      direction = "east",
      distance = 30,
    })
    assert.is_true(handled)
    local offset = container:getMovedOffset()
    assert.is_true(offset.x > 0)
  end)
end)
