describe("VerticalSpan", function()
  local VerticalSpan
  local logger

  setup(function()
    require("commonrequire")
    VerticalSpan = require("ui/widget/verticalspan")
    logger = require("logger")
  end)

  it("should create VerticalSpan with default height", function()
    local span = VerticalSpan:new()
    local size = span:getSize()
    assert.are.equal(0, size.w)
    assert.are.equal(0, size.h)
  end)

  it("should create VerticalSpan with custom height", function()
    local span = VerticalSpan:new({ height = 35 })
    local size = span:getSize()
    assert.are.equal(0, size.w)
    assert.are.equal(35, size.h)
  end)

  it("should warn and migrate width to height if width is set", function()
    local warned = false
    local orig_warn = logger.warn
    logger.warn = function(msg)
      warned = true
    end

    local span = VerticalSpan:new({ width = 50 })
    local size = span:getSize()
    assert.is_true(warned)
    assert.are.equal(0, size.w)
    assert.are.equal(50, size.h)
    assert.is_nil(span.width)
    assert.are.equal(50, span.height)

    logger.warn = orig_warn
  end)
end)
