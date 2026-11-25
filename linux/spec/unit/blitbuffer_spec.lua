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

  local function measureInvertAlloc(bb)
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
    return bytes_per_call
  end

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

    local bytes_per_call = measureInvertAlloc(bb)
    assert.is_true(bytes_per_call <= 150, string.format("expected <= 150 B/call, got %.2f", bytes_per_call))
    assert.are.equal(0xEE, bb:getPixel(0, 0).a)
  end)

  it("drops per-call FFI cast allocations while preserving all C blitter paths", function()
    assert.is_true(Blitbuffer.has_cblitbuffer)
    local was_cbb = Blitbuffer:getUseCBB()
    local was_jit = jit.status()
    local src8 = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8)
    local src8a = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8A)
    local dst8 = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BB8)
    local dst = Blitbuffer.new(8, 8, Blitbuffer.TYPE_BBRGB32)
    finally(function()
      collectgarbage("restart")
      if was_jit then
        jit.on()
      end
      Blitbuffer:enableCBB(was_cbb)
      dst:free()
      dst8:free()
      src8a:free()
      src8:free()
    end)

    Blitbuffer:enableCBB(true)
    src8:fill(Blitbuffer.Color8(0x20))
    src8:invertRect(0, 0, 4, 4)

    for y = 0, 7 do
      for x = 0, 7 do
        src8a:setPixel(x, y, Blitbuffer.Color8A(0x40, 0x80))
      end
    end

    dst:fill(Blitbuffer.Color8(0x00))
    dst:blendRectRGB32(0, 0, 2, 2, Blitbuffer.ColorRGB32(0x40, 0x80, 0xC0, 0xFF))
    assert.are.equal(0x40, dst:getPixel(0, 0).r)
    assert.are.equal(0x80, dst:getPixel(0, 0).g)
    assert.are.equal(0xC0, dst:getPixel(0, 0).b)

    dst:colorblitFromRGB32(src8, 2, 0, 0, 0, 2, 2, Blitbuffer.ColorRGB32(0x10, 0x20, 0x30, 0xFF))
    local p = dst:getPixel(2, 0)
    assert.are.equal(14, p.r)
    assert.are.equal(28, p.g)
    assert.are.equal(42, p.b)

    dst:colorblitFrom(src8, 4, 0, 0, 0, 2, 2, Blitbuffer.Color8A(0x80, 0xFF))
    p = dst:getPixel(4, 0)
    assert.are.equal(112, p.r)
    assert.are.equal(112, p.g)
    assert.are.equal(112, p.b)

    dst:blitFrom(src8, 0, 2, 0, 0, 2, 2)
    assert.are.equal(0xDF, dst:getPixel(0, 2).r)

    dst:lightenRect(4, 2, 2, 2, 0.5)
    assert.is_true(dst:getPixel(4, 2).r > 0)

    dst:paintRect(6, 2, 2, 2, Blitbuffer.Color8(0x80))
    assert.are.equal(0x80, dst:getPixel(6, 2).r)
    dst:darkenRect(6, 2, 1, 1, 0.5)
    assert.is_true(dst:getPixel(6, 2).r < 0x80)
    dst:multiplyRectRGB(7, 2, 1, 1, Blitbuffer.ColorRGB24(0xFF, 0x00, 0x00))
    assert.are.equal(0x80, dst:getPixel(7, 2).r)
    assert.are.equal(0x00, dst:getPixel(7, 2).g)

    dst:paintRectRGB32(0, 4, 2, 2, Blitbuffer.ColorRGB32(0x12, 0x34, 0x56, 0xFF))
    assert.are.equal(0x12, dst:getPixel(0, 4).r)
    assert.are.equal(0x34, dst:getPixel(0, 4).g)
    assert.are.equal(0x56, dst:getPixel(0, 4).b)
    dst:paintRoundedCorner(0, 4, 4, 4, 1, 2, Blitbuffer.Color8(0xFF))
    assert.are.equal(0xFF, dst:getPixel(2, 4).r)
    dst:hatchRect(4, 4, 4, 4, 1, Blitbuffer.Color8(0xAA))
    assert.are.equal(0xAA, dst:getPixel(4, 4).r)

    dst8:fill(Blitbuffer.Color8(0x00))
    dst8:ditheralphablitFrom(src8a, 2, 0, 0, 0, 2, 2)
    assert.are.equal(34, dst8:getPixel(2, 0).a)
    dst8:alphablitFrom(src8a, 0, 0, 0, 0, 2, 2)
    assert.are.equal(32, dst8:getPixel(0, 0).a)
    dst8:pmulalphablitFrom(src8a, 4, 0, 0, 0, 2, 2)
    assert.are.equal(64, dst8:getPixel(4, 0).a)
    dst8:ditherpmulalphablitFrom(src8a, 6, 0, 0, 0, 2, 2)
    assert.are.equal(68, dst8:getPixel(6, 0).a)
    dst8:ditherblitFrom(src8, 0, 2, 0, 0, 2, 2)
    assert.are.equal(238, dst8:getPixel(0, 2).a)
    assert.are.equal(221, dst8:getPixel(1, 2).a)
    dst8:invertblitFrom(src8, 2, 2, 0, 0, 2, 2)
    assert.are.equal(0x20, dst8:getPixel(2, 2).a)
    dst8:addblitFrom(src8, 4, 2, 0, 0, 2, 2, 0.5)
    assert.are.equal(111, dst8:getPixel(4, 2).a)

    assert.are.equal(0xDF, src8:getPixel(0, 0).a)
    assert.are.equal(0x20, src8:getPixel(5, 5).a)
    assert.are.equal(0x40, src8a:getPixel(0, 0).a)
    assert.are.equal(0x80, src8a:getPixel(0, 0).alpha)

    local bytes_per_call = measureInvertAlloc(src8)
    assert.are.equal(0, bytes_per_call, string.format("expected 0 B/call, got %.2f", bytes_per_call))
  end)
end)
