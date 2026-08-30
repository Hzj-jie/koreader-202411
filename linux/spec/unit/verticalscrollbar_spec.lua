local match = require("luassert.match")
local spy = require("luassert.spy")
local stub = require("luassert.stub")

describe("VerticalScrollBar module", function()
  local VerticalScrollBar, Screen, BD
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    BD = require("ui/bidi")
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
    end
  )
end)
