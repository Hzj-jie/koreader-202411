describe("RadioMark", function()
  local RadioMark
  local Blitbuffer

  setup(function()
    require("commonrequire")
    RadioMark = require("ui/widget/radiomark")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should initialize with checked = true", function()
    local mark = RadioMark:new({
      checked = true,
      enabled = true,
    })

    assert.truthy(mark[1])
    assert.are.equal("◉ ", mark[1].text)
    assert.are.equal(Blitbuffer.COLOR_BLACK, mark[1].fgcolor)
    assert.truthy(mark.baseline)
  end)

  it("should initialize with checked = false", function()
    local mark = RadioMark:new({
      checked = false,
      enabled = true,
    })

    assert.are.equal("◯ ", mark[1].text)
  end)

  it("should initialize with enabled = false", function()
    local mark = RadioMark:new({
      checked = true,
      enabled = false,
    })

    assert.are.equal(Blitbuffer.COLOR_DARK_GRAY, mark[1].fgcolor)
  end)

  it("should handle checkable = false (empty mark)", function()
    local mark = RadioMark:new({
      checkable = false,
    })

    assert.are.equal("", mark[1].text)
  end)
end)
