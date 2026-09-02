describe("HorizontalSpan", function()
  local HorizontalSpan

  setup(function()
    require("commonrequire")
    HorizontalSpan = require("ui/widget/horizontalspan")
  end)

  it("should create HorizontalSpan with default width", function()
    local span = HorizontalSpan:new()
    local size = span:getSize()
    assert.are.equal(0, size.w)
    assert.are.equal(0, size.h)
  end)

  it("should create HorizontalSpan with custom width", function()
    local span = HorizontalSpan:new({ width = 45 })
    local size = span:getSize()
    assert.are.equal(45, size.w)
    assert.are.equal(0, size.h)
  end)
end)
