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

  it("clamps negative length to 0 in checkBounds", function()
    local len = Blitbuffer.checkBounds(-15, 0, 0, 100, 100)
    assert.are.equal(0, len)
  end)

  it(
    "returns valid stride matching rotated dimensions in getBufferData for BBRGB24",
    function()
      local bb = Blitbuffer.new(10, 30, Blitbuffer.TYPE_BBRGB24)
      bb:rotate(90) -- Rotate 90 degrees: w becomes 30, h becomes 10
      local _, _, w, stride, _ = bb:getBufferData()
      bb:free()

      assert.are.equal(30, w)
      -- A row of width 30 in 24bpp requires at least 30 * 3 = 90 bytes stride.
      -- Unrotated stride of width 10 is only 30 bytes, causing row over-reads.
      assert.is_true(stride >= w * 3)
    end
  )
end)
