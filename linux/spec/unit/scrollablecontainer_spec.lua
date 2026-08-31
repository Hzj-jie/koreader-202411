local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("ScrollableContainer module", function()
  local ScrollableContainer, Widget, Screen, BD, Geom, Blitbuffer
  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Screen = require("device").screen
    BD = require("ui/bidi")
    ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  teardown(function()
    if Screen then
      Screen:setDPI(nil)
    end
  end)

  local function createContent(w, h)
    local content = Widget:new()
    content.getSize = function()
      return { w = w, h = h }
    end
    return content
  end

  it("should calculate scrollbar width", function()
    local container = ScrollableContainer:new({
      scroll_bar_width = 10,
    })
    assert.are.equal(30, container:getScrollbarWidth())
    assert.are.equal(15, container:getScrollbarWidth(5))
  end)

  it("should initialize ignore_events and key events", function()
    local container = ScrollableContainer:new({
      ignore_events = { "touch", "hold", "pan", "swipe", "key_pg_back", "key_pg_fwd" },
    })
    container:init()
    assert.is_nil(container.ges_events.ScrollableTouch)
    assert.is_nil(container.ges_events.ScrollableHold)
    assert.is_nil(container.ges_events.ScrollablePan)
    assert.is_nil(container.ges_events.ScrollableSwipe)
    assert.is_nil(container.key_events.ScrollPageUp)
    assert.is_nil(container.key_events.ScrollPageDown)
  end)

  it("should setup gutters and scrollbars correctly", function()
    Screen:setDPI(160)
    local content = createContent(170, 300)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()

    assert.is_not_nil(container._v_scroll_bar)
    assert.is_nil(container._h_scroll_bar)
    local expected_vgutter = container._v_scroll_bar:getRequiredWidth()
    assert.are.equal(200 - expected_vgutter, container._crop_w)

    local content2 = createContent(300, 170)
    local container2 = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content2,
    })
    container2:initState()

    assert.is_nil(container2._v_scroll_bar)
    assert.is_not_nil(container2._h_scroll_bar)
    local expected_hgutter = container2._h_scroll_bar:getRequiredHeight()
    assert.are.equal(200 - expected_hgutter, container2._crop_h)

    local content3 = createContent(300, 300)
    local container3 = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content3,
    })
    container3:initState()

    assert.is_not_nil(container3._v_scroll_bar)
    assert.is_not_nil(container3._h_scroll_bar)
    local v_gutter = container3._v_scroll_bar:getRequiredWidth()
    assert.are.equal(200 - v_gutter, container3._h_scroll_bar.width)
  end)

  it("handles non-scrollable content sizing and paintTo", function()
    local content = createContent(100, 100)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()
    assert.is_false(container._is_scrollable)
    assert.is_nil(container._v_scroll_bar)
    assert.is_nil(container._h_scroll_bar)

    local bb = {
      getType = function() return 1 end,
      blitFrom = function() end,
    }
    local painted_pos = {}
    content.paintTo = function(self, target_bb, x, y)
      painted_pos.x = x
      painted_pos.y = y
    end

    -- LTR paint
    local mirrored_stub = stub(BD, "mirroredUILayout", function() return false end)
    container:paintTo(bb, 10, 20)
    assert.are.equal(10, painted_pos.x)
    assert.are.equal(20, painted_pos.y)

    -- RTL paint (mirrored)
    mirrored_stub:revert()
    mirrored_stub = stub(BD, "mirroredUILayout", function() return true end)
    container:paintTo(bb, 10, 20)
    assert.are.equal(10 + (200 - 100), painted_pos.x)
    assert.are.equal(20, painted_pos.y)
    mirrored_stub:revert()

    -- Empty container paintTo
    local empty_container = ScrollableContainer:new({ width = 100, height = 100 })
    empty_container:paintTo(bb, 0, 0)
  end)

  it("should paint horizontal scrollbar with shift in RTL", function()
    local bb = {
      getType = function()
        return 1
      end,
      blitFrom = function() end,
    }
    local content = createContent(300, 300)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()

    container._h_scroll_bar.paintTo = spy.new(function() end)
    container._v_scroll_bar.paintTo = spy.new(function() end)

    local mirrored_stub = stub(BD, "mirroredUILayout", function()
      return false
    end)
    container:paintTo(bb, 50, 100)

    assert
      .spy(container._h_scroll_bar.paintTo)
      .was_called_with(container._h_scroll_bar, bb, 50, match._)
    container._h_scroll_bar.paintTo:clear()

    mirrored_stub:revert()
    mirrored_stub = stub(BD, "mirroredUILayout", function()
      return true
    end)

    container:paintTo(bb, 50, 100)

    local shift = container._v_scroll_bar:getRequiredWidth()
    assert
      .spy(container._h_scroll_bar.paintTo)
      .was_called_with(container._h_scroll_bar, bb, 50 + shift, match._)

    mirrored_stub:revert()
  end)

  it("should calculate scroll bounds and offsets", function()
    local content = createContent(500, 500)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()
    assert.is_table(container)
    assert.is_table(container:getScrolledOffset())
    container:setScrolledOffset({ x = 50, y = 50 })
    assert.are.equal(50, container._scroll_offset_x)
    assert.are.equal(50, container._scroll_offset_y)

    local crop = container:getCropRegion()
    assert.are.equal(container._crop_w, crop.w)
    assert.are.equal(container._crop_h, crop.h)
  end)

  it("should handle scroll reset and panning gestures", function()
    local content = createContent(500, 500)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()

    -- Test _scrollBy and setScrolledOffset
    container:_scrollBy(50, 50)
    assert.is_table(container:getScrolledOffset())
    container:setScrolledOffset({ x = 10, y = 10 })
    assert.are.equal(10, container._scroll_offset_x)
    assert.are.equal(10, container._scroll_offset_y)

    -- Test scrollToRatio
    container:scrollToRatio(0.5, 0.5)
    assert.is_table(container:getScrolledOffset())
    container:scrollToRatio(-1, -1)
    assert.are.equal(0, container._scroll_offset_x)
    assert.are.equal(0, container._scroll_offset_y)
    container:scrollToRatio(10, 10)
    assert.are.equal(container._max_scroll_offset_x, container._scroll_offset_x)
    assert.are.equal(container._max_scroll_offset_y, container._scroll_offset_y)

    container.dimen = Geom:new({ x = 0, y = 0, w = 200, h = 200 })

    -- Test touch events inside & outside
    assert.is_false(container:onScrollableTouch(nil, { pos = Geom:new({ x = 50, y = 50 }) }))
    assert.is_true(container._touch_pre_pan_was_inside)
    assert.is_false(container:onScrollableTouch(nil, { pos = Geom:new({ x = 500, y = 500 }) }))
    assert.is_false(container._touch_pre_pan_was_inside)

    -- Test pan gestures
    container:onScrollablePan(nil, { pos = Geom:new({ x = 50, y = 50 }), relative = { x = -20, y = -20 } })
    assert.is_true(container._scrolling)
    container:onScrollablePanRelease(nil, {})
    assert.is_false(container._scrolling)

    -- Pan outside without scrolling
    assert.is_false(container:onScrollablePan(nil, { pos = Geom:new({ x = 500, y = 500 }), relative = { x = -20, y = -20 } }))
    assert.is_false(container:onScrollablePanRelease(nil, {}))

    -- Test hold gestures
    assert.is_true(container:onScrollableHold(nil, { pos = Geom:new({ x = 50, y = 50 }) }))
    assert.is_false(container:onScrollableHold(nil, { pos = Geom:new({ x = 500, y = 500 }) }))
    assert.is_true(container:onScrollableHoldPan(nil, { pos = Geom:new({ x = 60, y = 60 }) }))
    assert.is_true(container:onScrollableHoldRelease(nil, { pos = Geom:new({ x = 80, y = 80 }) }))
    assert.is_false(container:onScrollableHoldRelease(nil, { pos = Geom:new({ x = 80, y = 80 }) }))

    -- HoldPan when not scrolling and not inside
    container._scrolling = false
    container._touch_pre_pan_was_inside = false
    assert.is_false(container:onScrollableHoldPan(nil, { pos = Geom:new({ x = 500, y = 500 }) }))

    -- Test swipe gestures in swipe_full_view = true
    container.swipe_full_view = true
    local directions = { "north", "south", "east", "west", "northeast", "northwest", "southeast", "southwest" }
    for _, dir in ipairs(directions) do
      assert.is_true(container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = dir, distance = 30 }))
    end
    -- Swipe outside
    assert.is_false(container:onScrollableSwipe(nil, { pos = Geom:new({ x = 500, y = 500 }), direction = "north" }))

    -- Test swipe gestures in swipe_full_view = false
    container.swipe_full_view = false
    for _, dir in ipairs(directions) do
      assert.is_true(container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = dir, distance = 30 }))
    end

    -- Page up/down
    container:onScrollPageUp()
    container:onScrollPageDown()

    -- Reset & onClose
    container:onClose()
    assert.is_nil(container._bb)
    container:reset()
    assert.is_nil(container._is_scrollable)
  end)

  it("handles non-scrollable gesture event guards", function()
    local content = createContent(100, 100)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()
    assert.is_false(container._is_scrollable)

    local dummy_ges = { pos = Geom:new({ x = 50, y = 50 }) }
    assert.is_false(container:onScrollableSwipe(nil, dummy_ges))
    assert.is_false(container:onScrollableTouch(nil, dummy_ges))
    assert.is_false(container:onScrollableHold(nil, dummy_ges))
    assert.is_false(container:onScrollableHoldPan(nil, dummy_ges))
    assert.is_false(container:onScrollableHoldRelease(nil, dummy_ges))
    assert.is_false(container:onScrollablePan(nil, dummy_ges))
    assert.is_false(container:onScrollablePanRelease(nil, dummy_ges))
    assert.is_false(container:onScrollPageUp())
    assert.is_false(container:onScrollPageDown())
  end)

  it("handles propagateEvent with scrollbars and gestures", function()
    local content = createContent(500, 500)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()
    container.dimen = Geom:new({ x = 0, y = 0, w = 200, h = 200 })

    -- Gesture outside bounds
    local outside_event = {
      handler = "onGesture",
      args = { { pos = Geom:new({ x = 500, y = 500 }) } },
    }
    assert.is_false(container:propagateEvent(outside_event))

    -- Scrollbar handled event
    local event_handled = { handler = "test" }
    local v_bar_stub = stub(container._v_scroll_bar, "handleEvent", function() return true end)
    assert.is_true(container:propagateEvent(event_handled))
    v_bar_stub:revert()

    local h_bar_stub = stub(container._h_scroll_bar, "handleEvent", function() return true end)
    assert.is_true(container:propagateEvent(event_handled))
    h_bar_stub:revert()

    -- Non-scrollable propagateEvent
    container._is_scrollable = false
    local called_child = false
    content.handleEvent = function()
      called_child = true
      return true
    end
    assert.is_true(container:propagateEvent({ handler = "test" }))
    assert.is_true(called_child)
  end)

  it("handles parent notification on page scroll", function()
    local content = createContent(200, 1000)
    local scrolled_row = nil
    local parent_mock = {
      _onPageScrollToRow = function(self, row)
        scrolled_row = row
      end,
    }
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      step_scroll_grid = {
        { top = 0, bottom = 100, row_num = 1 },
        { top = 101, bottom = 200, row_num = 2 },
      },
      [1] = content,
    })
    container:initState()
    container.showParent = function() return parent_mock end

    container:onScrollPageDown()
    assert.is_not_nil(scrolled_row)
  end)

  it("handles step scroll grid edge cases, truncation hiding and overflow", function()
    local content = createContent(200, 1000)
    local step_grid = {
      { top = 0, bottom = 100, content_top = 0, content_bottom = 90 },
      { top = 101, bottom = 200, content_top = 105, content_bottom = 195 },
      { top = 201, bottom = 300, content_top = 205, content_bottom = 295 },
      { top = 301, bottom = 400, content_top = 305, content_bottom = 395 },
      { top = 401, bottom = 500, content_top = 405, content_bottom = 495 },
      { top = 501, bottom = 600, content_top = 505, content_bottom = 595 },
    }
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      hide_truncated_grid_items = true,
      step_scroll_grid_func = function() return step_grid end,
      [1] = content,
    })
    container:initState()
    assert.is_not_nil(container.step_scroll_grid)

    -- Scroll down with step grid
    container:_scrollBy(0, 150, true)
    -- Scroll up with step grid
    container:_scrollBy(0, -150, true)

    -- Overflow top repeatedly
    container._scroll_offset_y = 0
    container:_scrollBy(0, -50, true)
    assert.are.equal(0, container._scroll_offset_y)

    -- Overflow bottom repeatedly
    container._scroll_offset_y = container._max_scroll_offset_y
    container:_scrollBy(0, 50, true)
    assert.are.equal(container._max_scroll_offset_y, container._scroll_offset_y)

    -- Test RTL scrollBy
    local mirrored_stub = stub(BD, "mirroredUILayout", function() return true end)
    local old_x = container._scroll_offset_x
    container:_scrollBy(10, 0)
    mirrored_stub:revert()
  end)
end)


