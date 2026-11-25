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

  it("reuses memoized cblitbuffer symbols within the allocation budget across GC", function()
    assert.is_true(Blitbuffer.has_cblitbuffer)
    local was_cbb = Blitbuffer:getUseCBB()
    local was_jit = jit.status()
    local bb = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8)
    finally(function()
      collectgarbage("restart")
      if was_jit then
        jit.on()
      end
      Blitbuffer:enableCBB(was_cbb)
      bb:free()
    end)

    Blitbuffer:enableCBB(true)
    bb:fill(Blitbuffer.Color8(0x11))
    bb:invertRect(0, 0, 1, 1)
    assert.are.equal(0xEE, bb:getPixel(0, 0).a)

    jit.off()
    for _ = 1, 100 do
      bb:invertRect(0, 0, 1, 1)
    end
    collectgarbage()
    collectgarbage()
    collectgarbage("stop")
    local before = collectgarbage("count") * 1024
    for _ = 1, 1000 do
      bb:invertRect(0, 0, 1, 1)
    end
    local bytes_per_call = (collectgarbage("count") * 1024 - before) / 1000
    collectgarbage("restart")
    assert.is_true(bytes_per_call <= 150, string.format("expected <= 150 B/call, got %.2f", bytes_per_call))
    assert.are.equal(0xEE, bb:getPixel(0, 0).a)
  end)
end)
