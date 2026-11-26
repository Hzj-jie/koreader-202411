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
end)
