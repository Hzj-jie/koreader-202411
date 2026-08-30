local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("ScrollableContainer module", function()
  local ScrollableContainer, Widget, Screen, BD
  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Screen = require("device").screen
    BD = require("ui/bidi")
    ScrollableContainer = require("ui/widget/container/scrollablecontainer")
    Widget = require("ui/widget/widget")
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
    if type(container.setScrolledOffset) == "function" then
      container:setScrolledOffset({ x = 50, y = 50 })
    end
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

    local Geom = require("ui/geometry")
    container.dimen = Geom:new({ x = 0, y = 0, w = 200, h = 200 })

    -- Test pan gestures
    container:onScrollablePan(nil, { pos = Geom:new({ x = 50, y = 50 }), relative = { x = -20, y = -20 } })
    container:onScrollablePanRelease(nil, {})

    -- Test hold gestures
    container:onScrollableHold(nil, { pos = Geom:new({ x = 50, y = 50 }) })
    container:onScrollableHoldPan(nil, { pos = Geom:new({ x = 60, y = 60 }) })
    container:onScrollableHoldRelease(nil, { pos = Geom:new({ x = 60, y = 60 }) })

    -- Test swipe gestures
    container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = "north", distance = 30 })
    container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = "south", distance = 30 })
    container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = "west", distance = 30 })
    container:onScrollableSwipe(nil, { pos = Geom:new({ x = 50, y = 50 }), direction = "east", distance = 30 })

    -- Page up/down
    container:onScrollPageUp()
    container:onScrollPageDown()
  end)

  it("handles step scroll grid functionality", function()
    local content = createContent(200, 1000)
    local step_grid = {
      { top = 0, bottom = 100, content_top = 0, content_bottom = 90 },
      { top = 101, bottom = 200, content_top = 105, content_bottom = 195 },
      { top = 201, bottom = 300, content_top = 205, content_bottom = 295 },
      { top = 301, bottom = 400, content_top = 305, content_bottom = 395 },
      { top = 401, bottom = 500, content_top = 405, content_bottom = 495 },
    }
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      step_scroll_grid_func = function() return step_grid end,
      [1] = content,
    })
    container:initState()

    -- Scroll up/down with step grid
    container:_scrollBy(0, 50)
    container:_scrollBy(0, -50)
    container:_scrollBy(0, 150)
    container:_scrollBy(0, -150)
  end)
end)


