local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("HorizontalScrollBar module", function()
  local HorizontalScrollBar, Screen, BD, Geom
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    BD = require("ui/bidi")
    Geom = require("ui/geometry")
    HorizontalScrollBar = require("ui/widget/horizontalscrollbar")
  end)

  teardown(function()
    if Screen then
      Screen:setDPI(nil)
    end
  end)

  it("should calculate correct required height with dynamic DPI", function()
    Screen:setDPI(160)
    local sb = HorizontalScrollBar:new({ height = 10 })
    assert.are.equal(3 * 10 + Screen:scaleBySize(5), sb:getRequiredHeight())

    Screen:setDPI(320)
    local sb2 = HorizontalScrollBar:new({ height = 20 })
    assert.are.equal(3 * 20 + Screen:scaleBySize(5), sb2:getRequiredHeight())
  end)

  it("should handle set(low, high)", function()
    local sb = HorizontalScrollBar:new()
    sb:set(0.3, 0.7)
    assert.are.equal(0.3, sb.low)
    assert.are.equal(0.7, sb.high)

    sb:set(-0.2, 1.4)
    assert.are.equal(0, sb.low)
    assert.are.equal(1, sb.high)
  end)

  it("should handle scroll callbacks on touch events in LTR and RTL", function()
    local scroll_ratio = nil
    local sb = HorizontalScrollBar:new({
      width = 200,
      scroll_callback = function(r)
        scroll_ratio = r
      end,
    })
    sb.touch_dimen = Geom:new({ x = 50, y = 0, w = 200, h = 30 })

    local ges = { pos = Geom:new({ x = 100, y = 10 }) }
    local res = sb:onTapScroll(nil, ges)
    assert.is_true(res)
    assert.are.equal(0.25, scroll_ratio) -- (100 - 50) / 200 = 50 / 200 = 0.25

    scroll_ratio = nil
    sb:onHoldScroll(nil, ges)
    assert.are.equal(0.25, scroll_ratio)

    scroll_ratio = nil
    sb:onHoldPanScroll(nil, ges)
    assert.are.equal(0.25, scroll_ratio)

    scroll_ratio = nil
    sb:onHoldReleaseScroll(nil, ges)
    assert.are.equal(0.25, scroll_ratio)

    scroll_ratio = nil
    sb:onPanScroll(nil, ges)
    assert.are.equal(0.25, scroll_ratio)

    scroll_ratio = nil
    sb:onPanScrollRelease(nil, ges)
    assert.are.equal(0.25, scroll_ratio)

    -- RTL mode
    local mirrored_stub = stub(BD, "mirroredUILayout", function() return true end)
    scroll_ratio = nil
    sb:onTapScroll(nil, ges)
    assert.are.equal(0.75, scroll_ratio) -- 1 - 0.25 = 0.75
    mirrored_stub:revert()
  end)

  it("should calculate correct touch_dimen and draw separator line in LTR and RTL", function()
    local bb = {
      paintRect = spy.new(function() end),
      paintBorder = spy.new(function() end),
    }

    local sb = HorizontalScrollBar:new({
      width = 100,
      height = 10,
      bordersize = 1,
      radius = 0,
      bordercolor = 0,
      rectcolor = 0,
    })
    sb:paintTo(bb, 50, 100)

    -- Touch dimen: y = 100 - 10 = 90, h = 3 * 10 = 30
    assert.are.equal(90, sb.touch_dimen.y)
    assert.are.equal(30, sb.touch_dimen.h)

    -- Separator line: y - height = 100 - 10 = 90
    assert.spy(bb.paintRect).was_called_with(bb, 50, 90, 100, 1, match._)

    -- RTL painting
    bb.paintRect:clear()
    local mirrored_stub = stub(BD, "mirroredUILayout", function() return true end)
    sb:paintTo(bb, 50, 100)
    assert.spy(bb.paintRect).was_called()
    mirrored_stub:revert()

    -- Disabled painting
    sb.enable = false
    bb.paintRect:clear()
    sb:paintTo(bb, 0, 0)
    assert.spy(bb.paintRect).was_not_called()
  end)
end)
