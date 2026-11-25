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

  describe("blitTo4bpp (BB_blit_to_4bpp)", function()
    local ffi

    setup(function()
      ffi = require("ffi")
    end)

    it(
      "packs odd and even BB8 rects into padded 4bpp buffer without clobbering neighbors",
      function()
        -- 7x4 physical size: 4bpp min row bytes = 4, test with padded stride = 6.
        local src = Blitbuffer.new(7, 4, Blitbuffer.TYPE_BB8)
        local hw_stride = 6
        local hw_buf = ffi.new("uint8_t[?]", hw_stride * 4)
        for i = 0, hw_stride * 4 - 1 do
          hw_buf[i] = 0xA5
        end

        for y = 0, 3 do
          for x = 0, 6 do
            src:setPixel(x, y, Blitbuffer.Color8(y * 0x20 + x * 0x10))
          end
        end

        -- Partial flush at x=1, w=3 (starts odd, ends even) on row 1.
        src:blitTo4bpp(hw_buf, hw_stride, 1, 1, 3, 1, false)
        -- Row 0 untouched sentinel 0xA5
        for c = 0, hw_stride - 1 do
          assert.are.equal(0xA5, hw_buf[c])
        end
        -- Row 1: x=0 preserves 0xA, x=1 gets 0x3, x=2 gets 0x4, x=3 gets 0x5, x=4..6 preserve 0xA5
        assert.are.equal(0xA3, hw_buf[hw_stride * 1 + 0])
        assert.are.equal(0x45, hw_buf[hw_stride * 1 + 1])
        assert.are.equal(0xA5, hw_buf[hw_stride * 1 + 2])
        assert.are.equal(0xA5, hw_buf[hw_stride * 1 + 3])
        assert.are.equal(0xA5, hw_buf[hw_stride * 1 + 4])
        assert.are.equal(0xA5, hw_buf[hw_stride * 1 + 5])

        -- Row 2, x=4, w=1 (even x, single nibble): x=4 gets (0x80 -> 0x8), x=5 preserves 0x5 -> 0x85
        src:blitTo4bpp(hw_buf, hw_stride, 4, 2, 1, 1, false)
        assert.are.equal(0xA5, hw_buf[hw_stride * 2 + 0])
        assert.are.equal(0xA5, hw_buf[hw_stride * 2 + 1])
        assert.are.equal(0x85, hw_buf[hw_stride * 2 + 2])
        assert.are.equal(0xA5, hw_buf[hw_stride * 2 + 3])

        -- Inverted flush across full 7x4 (odd width 7 leaves lower nibble of byte 3 untouched!)
        src:blitTo4bpp(hw_buf, hw_stride, 0, 0, 7, 4, true)
        -- Row 0 values inverted: [0x0,0x1,0x2,0x3,0x4,0x5,0x6] ^ 0xF = [0xF,0xE,0xD,0xC,0xB,0xA,0x9]
        assert.are.equal(0xFE, hw_buf[0])
        assert.are.equal(0xDC, hw_buf[1])
        assert.are.equal(0xBA, hw_buf[2])
        assert.are.equal(0x95, hw_buf[3])
        assert.are.equal(0xA5, hw_buf[4])
        assert.are.equal(0xA5, hw_buf[5])

        -- Out-of-bounds / empty rects are safe no-ops and void* dst converts cleanly
        local void_dst = ffi.cast("void *", hw_buf)
        src:blitTo4bpp(void_dst, hw_stride, 10, 0, 2, 2, false)
        src:blitTo4bpp(void_dst, hw_stride, 0, 0, 0, 4, false)
        src:blitTo4bpp(void_dst, hw_stride, 6, 3, 100, 100, false)
        -- Pixel (6,3): value 3*0x20 + 6*0x10 = 0xC0 -> upper nibble 0xC, lower stays 0x5
        assert.are.equal(0xC5, hw_buf[hw_stride * 3 + 3])

        src:free()
      end
    )
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
