describe("RectSpan", function()
  local RectSpan

  setup(function()
    require("commonrequire")
    RectSpan = require("ui/widget/rectspan")
  end)

  it("should create RectSpan with default width and height", function()
    local span = RectSpan:new()
    local size = span:getSize()
    assert.are.equal(0, size.w)
    assert.are.equal(0, size.h)
  end)

  it("should create RectSpan with custom width and height", function()
    local span = RectSpan:new({ width = 30, height = 40 })
    local size = span:getSize()
    assert.are.equal(30, size.w)
    assert.are.equal(40, size.h)
  end)
end)
