local match = require("luassert.match")
local spy = require("luassert.spy")

describe("HorizontalScrollBar module", function()
  local HorizontalScrollBar, Screen
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
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

  it("should calculate correct touch_dimen and draw separator line", function()
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
  end)
end)
