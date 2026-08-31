describe("MovableContainer widget", function()
  local MovableContainer, Blitbuffer, BD, Device, Geom, Widget, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MovableContainer = require("ui/widget/container/movablecontainer")
    Blitbuffer = require("ffi/blitbuffer")
    BD = require("ui/bidi")
    Device = require("device")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
    Screen = Device.screen
  end)

  it("should initialize with default parameters, ignore_events, and unmovable flag", function()
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
    assert.is_not_nil(container.ges_events)
    assert.is_not_nil(container.ges_events.MovableSwipe)

    -- With ignore_events
    local container_ignored = MovableContainer:new({
      [1] = inner_widget,
      ignore_events = { "touch", "swipe", "hold", "hold_pan", "hold_release", "pan", "pan_release" },
    })
    assert.is_nil(container_ignored.ges_events.MovableTouch)
    assert.is_nil(container_ignored.ges_events.MovableSwipe)
    assert.is_nil(container_ignored.ges_events.MovableHold)

    -- With unmovable
    local unmovable = MovableContainer:new({
      [1] = inner_widget,
      unmovable = true,
    })
    assert.is_nil(unmovable.ges_events)

    -- When not touch device
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return false end
    local non_touch = MovableContainer:new({
      [1] = inner_widget,
    })
    assert.is_nil(non_touch.ges_events)
    Device.isTouchDevice = orig_is_touch
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

    container:setMovedOffset(nil)
    assert.are.equal(20, container._moved_offset_x)

    container:setMovedOffset(Geom:new({ x = 0, y = 0 }))
    offset = container:getMovedOffset()
    assert.are.equal(0, offset.x)
    assert.are.equal(0, offset.y)
  end)

  it("should handle ensureAnchor under various positioning scenarios", function()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local inner_widget = Widget:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      getSize = function() return Geom:new({ x = 0, y = 0, w = 100, h = 50 }) end,
    })

    -- No anchor
    local c_no_anchor = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
    })
    c_no_anchor:ensureAnchor(10, 10)
    assert.are.equal(0, c_no_anchor._moved_offset_x)

    -- Anchor with room above (standard popup above)
    local c_above = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = Geom:new({ x = 200, y = 300, w = 80, h = 40 }),
    })
    c_above:ensureAnchor(0, 0)
    assert.are.equal(200, c_above._moved_offset_x)
    assert.are.equal(300 - 50, c_above._moved_offset_y)

    -- Anchor with prefers_pop_down function
    local c_pop_down = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = function()
        return Geom:new({ x = 200, y = 300, w = 80, h = 40 }), true
      end,
    })
    c_pop_down:ensureAnchor(0, 0)
    assert.are.equal(200, c_pop_down._moved_offset_x)
    assert.are.equal(300 + 40, c_pop_down._moved_offset_y)

    -- Anchor near top (no room above, room below)
    local c_below = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = Geom:new({ x = 50, y = 10, w = 80, h = 40 }),
    })
    c_below:ensureAnchor(0, 0)
    assert.are.equal(50, c_below._moved_offset_x)
    assert.are.equal(10 + 40, c_below._moved_offset_y)

    -- Anchor clamped horizontally to left < 0 and right > screen_w
    local c_left_clamp = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = Geom:new({ x = -20, y = 200, w = 80, h = 40 }),
    })
    c_left_clamp:ensureAnchor(0, 0)
    assert.are.equal(0, c_left_clamp._moved_offset_x)

    local c_right_clamp = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = Geom:new({ x = screen_w - 50, y = 200, w = 80, h = 40 }),
    })
    c_right_clamp:ensureAnchor(0, 0)
    assert.are.equal(screen_w - 100, c_right_clamp._moved_offset_x)

    -- RTL layout
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end
    local c_rtl = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      anchor = Geom:new({ x = 200, y = 300, w = 80, h = 40 }),
    })
    c_rtl:ensureAnchor(0, 0)
    assert.are.equal(200 + 80 - 100, c_rtl._moved_offset_x)
    BD.mirroredUILayout = orig_mirrored

    -- Insufficient room above and below: h_remaining_if_above >= h_remaining_if_below
    local big_widget = Widget:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = screen_h }),
      getSize = function() return Geom:new({ x = 0, y = 0, w = 100, h = screen_h }) end,
    })
    local c_tight_top = MovableContainer:new({
      [1] = big_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = screen_h }),
      anchor = Geom:new({ x = 50, y = math.floor(screen_h / 2), w = 80, h = math.floor(screen_h / 2) }),
    })
    c_tight_top:ensureAnchor(0, 0)
    assert.are.equal(0, c_tight_top._moved_offset_y)

    -- Insufficient room above and below: h_remaining_if_above < h_remaining_if_below
    local c_tight_bottom = MovableContainer:new({
      [1] = big_widget,
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = screen_h }),
      anchor = Geom:new({ x = 50, y = 10, w = 80, h = 10 }),
    })
    c_tight_bottom:ensureAnchor(0, 0)
    assert.are.equal(screen_h - screen_h, c_tight_bottom._moved_offset_y)
  end)

  it("should paint to target blitbuffer with and without alpha and handle compose_bb cache lifecycle", function()
    local painted_target = nil
    local painted_x, painted_y = nil, nil
    local child = Widget:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 50 }),
      getSize = function() return Geom:new({ x = 0, y = 0, w = 100, h = 50 }) end,
      paintTo = function(self, target_bb, x, y)
        painted_target = target_bb
        painted_x = x
        painted_y = y
      end,
    })

    -- Nil child
    local empty_container = MovableContainer:new({})
    empty_container:paintTo(nil, 0, 0)

    -- Without alpha, with anchor
    local container = MovableContainer:new({
      [1] = child,
      anchor = Geom:new({ x = 200, y = 200, w = 50, h = 30 }),
    })
    local target_bb = Blitbuffer.new(400, 400)
    container:paintTo(target_bb, 0, 0)
    assert.is_true(container._anchor_ensured)
    assert.are.equal(target_bb, painted_target)
    assert.are.equal(200, painted_x)

    -- Dirty region calculation
    local dirty = container:dirtyRegion()
    assert.are.equal(200, dirty.x)

    -- With alpha
    local container_alpha = MovableContainer:new({
      [1] = child,
      alpha = 0.7,
      dimen = Geom:new({ x = 10, y = 10, w = 100, h = 50 }),
    })
    container_alpha:paintTo(target_bb, 10, 10)
    assert.is_not_nil(container_alpha.compose_bb)
    assert.are.equal(400, container_alpha.compose_bb:getWidth())
    assert.are.equal(400, container_alpha.compose_bb:getHeight())
    assert.are.equal(container_alpha.compose_bb, painted_target)

    -- Resizing target blitbuffer forces compose_bb re-creation
    local target_bb_large = Blitbuffer.new(600, 600)
    container_alpha:paintTo(target_bb_large, 10, 10)
    assert.are.equal(600, container_alpha.compose_bb:getWidth())
    assert.are.equal(600, container_alpha.compose_bb:getHeight())

    -- onClose frees compose_bb
    container_alpha:onClose()
    assert.is_nil(container_alpha.compose_bb)

    target_bb:free()
    target_bb_large:free()
  end)

  it("should handle _moveBy boundary constraints and hold alpha toggles", function()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local child = Widget:new({
      dimen = Geom:new({ x = 50, y = 50, w = 100, h = 50 }),
      getSize = function() return Geom:new({ x = 50, y = 50, w = 100, h = 50 }) end,
    })
    local container = MovableContainer:new({
      [1] = child,
      dimen = Geom:new({ x = 50, y = 50, w = 100, h = 50 }),
    })

    -- Unconstrained move
    container:_moveBy(25, 35, false)
    assert.are.equal(25, container._moved_offset_x)
    assert.are.equal(35, container._moved_offset_y)

    -- Move with restrict_to_screen exceeding top-left
    container:_moveBy(-200, -200, true)
    assert.are.equal(-50, container._moved_offset_x)
    assert.are.equal(-50, container._moved_offset_y)

    -- Move with restrict_to_screen exceeding bottom-right
    container:_moveBy(screen_w * 2, screen_h * 2, true)
    assert.are.equal(screen_w - 50 - 100, container._moved_offset_x)
    assert.are.equal(screen_h - 50 - 50, container._moved_offset_y)

    -- Hold with no move while moved -> resets position
    container:_moveBy()
    assert.are.equal(0, container._moved_offset_x)
    assert.are.equal(0, container._moved_offset_y)

    -- Hold with no move while unmoved -> toggles alpha
    container:_moveBy()
    assert.are.equal(0.6, container.alpha)
    container:_moveBy()
    assert.is_nil(container.alpha)
  end)

  it("should handle all 8 directions in onMovableSwipe", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }),
    })

    -- Unpainted container (dimen is nil)
    local unpainted = MovableContainer:new({ [1] = inner_widget })
    assert.is_false(unpainted:onMovableSwipe(nil, { pos = Geom:new({ x = 110, y = 110 }) }))

    -- Swipe outside container
    assert.is_false(container:onMovableSwipe(nil, {
      pos = Geom:new({ x = 10, y = 10 }),
      direction = "east",
      distance = 20,
    }))

    local directions = { "north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest" }
    for _, dir in ipairs(directions) do
      container:setMovedOffset(Geom:new({ x = 0, y = 0 }))
      local res = container:onMovableSwipe(nil, {
        pos = Geom:new({ x = 120, y = 120 }),
        direction = dir,
        distance = 30,
      })
      assert.is_true(res)
    end
  end)

  it("should handle onMovableTouch, onMovableHold, onMovableHoldPan, and onMovableHoldRelease", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }),
    })

    -- Unpainted container returns false
    local unpainted = MovableContainer:new({ [1] = inner_widget })
    assert.is_false(unpainted:onMovableTouch(nil, { pos = Geom:new({ x = 110, y = 110 }) }))
    assert.is_false(unpainted:onMovableHold(nil, { pos = Geom:new({ x = 110, y = 110 }) }))
    assert.is_false(unpainted:onMovableHoldPan(nil, { pos = Geom:new({ x = 110, y = 110 }) }))
    assert.is_false(unpainted:onMovableHoldRelease(nil, { pos = Geom:new({ x = 110, y = 110 }) }))

    -- Touch inside and outside
    assert.is_false(container:onMovableTouch(nil, { pos = Geom:new({ x = 120, y = 120 }) }))
    assert.is_true(container._touch_pre_pan_was_inside)
    assert.is_false(container:onMovableTouch(nil, { pos = Geom:new({ x = 10, y = 10 }) }))
    assert.is_false(container._touch_pre_pan_was_inside)

    -- Hold inside and outside
    assert.is_false(container:onMovableHold(nil, { pos = Geom:new({ x = 10, y = 10 }) }))
    assert.is_false(container._moving)
    assert.is_true(container:onMovableHold(nil, { pos = Geom:new({ x = 120, y = 120 }) }))
    assert.is_true(container._moving)

    -- HoldPan
    assert.is_true(container:onMovableHoldPan(nil, { pos = Geom:new({ x = 150, y = 150 }) }))

    -- HoldRelease with large movement
    assert.is_true(container:onMovableHoldRelease(nil, { pos = Geom:new({ x = 160, y = 170 }) }))
    assert.are.equal(40, container._moved_offset_x)
    assert.are.equal(50, container._moved_offset_y)

    -- HoldRelease without moving or prior touch
    assert.is_false(container:onMovableHoldRelease(nil, { pos = Geom:new({ x = 160, y = 170 }) }))

    -- HoldRelease with missing relative start coordinates
    container._moving = true
    container._move_relative_x = nil
    assert.is_false(container:onMovableHoldRelease(nil, { pos = Geom:new({ x = 160, y = 170 }) }))
    container:resetEventState()

    -- HoldPan with _touch_pre_pan_was_inside
    container._touch_pre_pan_was_inside = true
    assert.is_true(container:onMovableHoldPan(nil, { pos = Geom:new({ x = 10, y = 10 }) }))
    assert.is_false(container._touch_pre_pan_was_inside)
    assert.is_true(container._moving)
    container:resetEventState()

    -- HoldPan outside without moving
    assert.is_false(container:onMovableHoldPan(nil, { pos = Geom:new({ x = 10, y = 10 }) }))
  end)

  it("should handle onMovablePan, onMovablePanRelease, and resetEventState", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }) })
    local container = MovableContainer:new({
      [1] = inner_widget,
      dimen = Geom:new({ x = 100, y = 100, w = 100, h = 100 }),
    })

    -- Unpainted container returns false
    local unpainted = MovableContainer:new({ [1] = inner_widget })
    assert.is_false(unpainted:onMovablePan(nil, { pos = Geom:new({ x = 110, y = 110 }) }))
    assert.is_false(unpainted:onMovablePanRelease(nil, { pos = Geom:new({ x = 110, y = 110 }) }))

    -- Pan outside without prior touch or moving
    assert.is_false(container:onMovablePan(nil, {
      pos = Geom:new({ x = 10, y = 10 }),
      relative = Geom:new({ x = 5, y = 5 }),
    }))

    -- Pan inside
    assert.is_true(container:onMovablePan(nil, {
      pos = Geom:new({ x = 120, y = 120 }),
      relative = Geom:new({ x = 15, y = 25 }),
    }))
    assert.is_true(container._moving)
    assert.are.equal(15, container._move_relative_x)
    assert.are.equal(25, container._move_relative_y)

    -- PanRelease
    assert.is_true(container:onMovablePanRelease(nil, {}))
    assert.is_false(container._moving)
    assert.are.equal(15, container._moved_offset_x)
    assert.are.equal(25, container._moved_offset_y)

    -- PanRelease when not moving
    assert.is_false(container:onMovablePanRelease(nil, {}))

    -- resetEventState
    container._touch_pre_pan_was_inside = true
    container._moving = true
    container:resetEventState()
    assert.is_false(container._touch_pre_pan_was_inside)
    assert.is_false(container._moving)
  end)
end)
