local Blitbuffer

describe("ffi/blitbuffer module", function()
  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("creates buffers and queries basic properties", function()
    local bb = Blitbuffer.new(100, 50, Blitbuffer.TYPE_BBRGB32)
    assert.is_not_nil(bb)
    assert.are.equal(100, bb:getWidth())
    assert.are.equal(50, bb:getHeight())
    assert.are.equal(Blitbuffer.TYPE_BBRGB32, bb:getType())
    bb:free()
  end)

  it("handles checkBounds with valid positive bounds and offsets", function()
    local len, toff, soff = Blitbuffer.checkBounds(50, 10, 20, 100, 100)
    assert.are.equal(50, len)
    assert.are.equal(10, toff)
    assert.are.equal(20, soff)

    -- Clipping when length exceeds available space
    len, toff, soff = Blitbuffer.checkBounds(95, 10, 20, 100, 100)
    assert.are.equal(80, len) -- source has 100 - 20 = 80 left
    assert.are.equal(10, toff)
    assert.are.equal(20, soff)
  end)
end)
