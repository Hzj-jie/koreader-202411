local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("ScrollableContainer module", function()
  local ScrollableContainer, Widget, Screen, BD
  setup(function()
    require("commonrequire")
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

  -- Helper to create a dummy content widget with specified size
  local function createContent(w, h)
    local content = Widget:new()
    content.getSize = function()
      return { w = w, h = h }
    end
    return content
  end

  it("should setup gutters and scrollbars correctly", function()
    Screen:setDPI(160)
    -- Container size: 200x200
    -- Content size: 170x300 (vertical scrollbar needed, fits horizontally with gutter)
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

    -- Container size: 200x200
    -- Content size: 300x170 (horizontal scrollbar needed, fits vertically with gutter)
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

    -- Container size: 200x200
    -- Content size: 300x300 (both needed)
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
    -- Horizontal scrollbar width should be reduced by v_gutter to not overlap
    assert.are.equal(200 - v_gutter, container3._h_scroll_bar.width)
  end)

  it("should paint horizontal scrollbar with shift in RTL", function()
    local bb = {
      getType = function()
        return 1
      end,
      blitFrom = function() end,
    }
    -- Container size: 200x200, content: 300x300 (both scrollbars)
    local content = createContent(300, 300)
    local container = ScrollableContainer:new({
      width = 200,
      height = 200,
      [1] = content,
    })
    container:initState()

    -- Spy on paintTo of scrollbars
    container._h_scroll_bar.paintTo = spy.new(function() end)
    container._v_scroll_bar.paintTo = spy.new(function() end)

    -- Test LTR
    local mirrored_stub = stub(BD, "mirroredUILayout", function()
      return false
    end)
    container:paintTo(bb, 50, 100)

    -- In LTR, horizontal scrollbar is painted at x
    assert
      .spy(container._h_scroll_bar.paintTo)
      .was_called_with(container._h_scroll_bar, bb, 50, match._)
    container._h_scroll_bar.paintTo:clear()

    -- Test RTL
    mirrored_stub:revert()
    mirrored_stub = stub(BD, "mirroredUILayout", function()
      return true
    end)

    container:paintTo(bb, 50, 100)

    -- In RTL, horizontal scrollbar is painted at x + shift (shift = v_gutter)
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
    container:_scrollBy(10, 10)
  end)
end)
