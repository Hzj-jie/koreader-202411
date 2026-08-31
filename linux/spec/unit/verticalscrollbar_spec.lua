local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("VerticalScrollBar module", function()
  local VerticalScrollBar, Screen, BD, Geom
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    BD = require("ui/bidi")
    Geom = require("ui/geometry")
    VerticalScrollBar = require("ui/widget/verticalscrollbar")
  end)

  teardown(function()
    if Screen then
      Screen:setDPI(nil)
    end
  end)

  it("should calculate correct required width with dynamic DPI", function()
    Screen:setDPI(160)
    local sb = VerticalScrollBar:new({ width = 10 })
    assert.are.equal(3 * 10 + Screen:scaleBySize(5), sb:getRequiredWidth())

    Screen:setDPI(320)
    local sb2 = VerticalScrollBar:new({ width = 20 })
    assert.are.equal(3 * 20 + Screen:scaleBySize(5), sb2:getRequiredWidth())
  end)

  it("should handle set(low, high)", function()
    local sb = VerticalScrollBar:new()
    sb:set(0.2, 0.8)
    assert.are.equal(0.2, sb.low)
    assert.are.equal(0.8, sb.high)

    sb:set(-0.5, 1.5)
    assert.are.equal(0, sb.low)
    assert.are.equal(1, sb.high)
  end)

  it("should handle scroll callbacks on touch events", function()
    local scroll_ratio = nil
    local sb = VerticalScrollBar:new({
      height = 200,
      scroll_callback = function(r)
        scroll_ratio = r
      end,
    })
    sb.touch_dimen = Geom:new({ x = 0, y = 100, w = 30, h = 200 })

    local ges = { pos = Geom:new({ x = 10, y = 150 }) }
    local res = sb:onTapScroll(nil, ges)
    assert.is_true(res)
    assert.are.equal(0.25, scroll_ratio) -- (150 - 100) / 200 = 50 / 200 = 0.25

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
  end)

  it(
    "should calculate correct touch_dimen and draw separator line on correct side",
    function()
      local bb = {
        paintRect = spy.new(function() end),
        paintBorder = spy.new(function() end),
      }

      -- Test LTR
      local mirrored_stub = stub(BD, "mirroredUILayout", function()
        return false
      end)
      local sb = VerticalScrollBar:new({
        width = 10,
        height = 100,
        bordersize = 1,
        radius = 0,
        bordercolor = 0,
        rectcolor = 0,
      })
      sb:paintTo(bb, 50, 100)

      -- Touch dimen: x = 50 - 10 = 40, w = 3 * 10 = 30
      assert.are.equal(40, sb.touch_dimen.x)
      assert.are.equal(30, sb.touch_dimen.w)

      -- Separator line: LTR => x - width = 50 - 10 = 40
      assert.spy(bb.paintRect).was_called_with(bb, 40, 100, 1, 100, match._)
      bb.paintRect:clear()

      -- Test RTL
      mirrored_stub:revert()
      mirrored_stub = stub(BD, "mirroredUILayout", function()
        return true
      end)

      sb:paintTo(bb, 50, 100)

      -- Separator line: RTL => x + 2 * width - border = 50 + 20 - 1 = 69
      assert.spy(bb.paintRect).was_called_with(bb, 69, 100, 1, 100, match._)

      mirrored_stub:revert()

      -- When enable is false
      sb.enable = false
      bb.paintRect:clear()
      sb:paintTo(bb, 0, 0)
      assert.spy(bb.paintRect).was_not_called()
    end
  )
end)
