require("ffi_wrapper")

local Blitbuffer = require("ffi/blitbuffer")

describe("Blitbuffer unit tests", function()
  describe("Color conversion", function()
    -- 0xFF = 0b11111111
    -- 0xAA = 0b10101010
    -- 0x55 = 0b01010101
    local cRGB32 = Blitbuffer.ColorRGB32(0xFF, 0xAA, 0x55, 0x00)
    local cRGB24 = Blitbuffer.ColorRGB24(0xFF, 0xAA, 0x55) -- luacheck: ignore 211
    local cRGB24_32 = cRGB32:getColorRGB24() -- luacheck: ignore 211

    local whiteRGB32 = Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFF, 0x00)
    local whiteRGB32a = Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFF, 0xFF)
    local whiteRGB24 = Blitbuffer.ColorRGB24(0xFF, 0xFF, 0xFF)
    local whiteRGB16 = Blitbuffer.ColorRGB16(0xFFFF)
    local whiteBB8A = Blitbuffer.Color8A(0xFF, 0x00)
    local whiteBB8Aa = Blitbuffer.Color8A(0xFF, 0xFF)
    local whiteBB8 = Blitbuffer.Color8(0xFF)
    local whiteBB4L = Blitbuffer.Color4L(0x0F)
    local whiteBB4U = Blitbuffer.Color4U(0xF0)
    local blackRGB32 = Blitbuffer.ColorRGB32(0x00, 0x00, 0x00, 0x00)
    local blackRGB32a = Blitbuffer.ColorRGB32(0x00, 0x00, 0x00, 0xFF)
    local blackRGB24 = Blitbuffer.ColorRGB24(0x00, 0x00, 0x00)
    local blackRGB16 = Blitbuffer.ColorRGB16(0x0000)
    local blackBB8A = Blitbuffer.Color8A(0x00, 0x00)
    local blackBB8Aa = Blitbuffer.Color8A(0x00, 0xFF)
    local blackBB8 = Blitbuffer.Color8(0x00)
    local blackBB4L = Blitbuffer.Color4L(0x00)
    local blackBB4U = Blitbuffer.Color4U(0x00)

    it("should convert RGB32 to RGB16", function()
      local c16_32 = cRGB32:getColorRGB16()
      assert.are.equals(0xFD4A, c16_32.v)
      assert.are.equal(c16_32:getR(), 0xFF) -- 0b11111 111
      assert.are.equal(c16_32:getG(), 0xAA) -- 0b101010 10
      assert.are.equal(c16_32:getB(), 0x52) -- 0b01010 010
    end)

    it("should convert RGB32 to gray8", function()
      local c8_32 = cRGB32:getColor8()
      assert.are.equals(0xB9, c8_32.a)
    end)

    it("should convert RGB32 to gray4 (lower nibble)", function()
      local c4l_32 = cRGB32:getColor4L()
      assert.are.equals(0x0B, c4l_32.a)
    end)

    it("should convert RGB32 to gray4 (upper nibble)", function()
      local c4u_32 = cRGB32:getColor4U()
      assert.are.equals(0xB0, c4u_32.a)
    end)

    describe(
      "should have pure white stay pure white when converting",
      function()
        it("from RGB32 with alpha 0x00", function()
          assert.True(whiteRGB32:getColorRGB32() == whiteRGB32)
          assert.True(whiteRGB32:getColorRGB24() == whiteRGB24)
          assert.True(whiteRGB32:getColorRGB16() == whiteRGB16)
          assert.True(whiteRGB32:getColor8() == whiteBB8)
          assert.True(whiteRGB32:getColor8A() == whiteBB8A)
          assert.True(whiteRGB32:getColor4L() == whiteBB4L)
          assert.True(whiteRGB32:getColor4U() == whiteBB4U)
        end)
        it("from RGB32 with alpha 0xFF", function()
          assert.True(whiteRGB32a:getColorRGB32() == whiteRGB32a)
          assert.True(whiteRGB32a:getColorRGB24() == whiteRGB24)
          assert.True(whiteRGB32a:getColorRGB16() == whiteRGB16)
          assert.True(whiteRGB32a:getColor8() == whiteBB8)
          assert.True(whiteRGB32a:getColor8A() == whiteBB8Aa)
          assert.True(whiteRGB32a:getColor4L() == whiteBB4L)
          assert.True(whiteRGB32a:getColor4U() == whiteBB4U)
        end)
        it("from RGB24", function()
          assert.True(whiteRGB24:getColorRGB32() == whiteRGB32a)
          assert.True(whiteRGB24:getColorRGB24() == whiteRGB24)
          assert.True(whiteRGB24:getColorRGB16() == whiteRGB16)
          assert.True(whiteRGB24:getColor8() == whiteBB8)
          assert.True(whiteRGB24:getColor8A() == whiteBB8Aa)
          assert.True(whiteRGB24:getColor4L() == whiteBB4L)
          assert.True(whiteRGB24:getColor4U() == whiteBB4U)
        end)
        it("from RGB16", function()
          assert.True(whiteRGB16:getColorRGB32() == whiteRGB32a)
          assert.True(whiteRGB16:getColorRGB24() == whiteRGB24)
          assert.True(whiteRGB16:getColorRGB16() == whiteRGB16)
          assert.True(whiteRGB16:getColor8() == whiteBB8)
          assert.True(whiteRGB16:getColor8A() == whiteBB8Aa)
          assert.True(whiteRGB16:getColor4L() == whiteBB4L)
          assert.True(whiteRGB16:getColor4U() == whiteBB4U)
        end)
        it("from BB8A with alpha 0x00", function()
          assert.True(whiteBB8A:getColorRGB32() == whiteRGB32)
          assert.True(whiteBB8A:getColorRGB24() == whiteRGB24)
          assert.True(whiteBB8A:getColorRGB16() == whiteRGB16)
          assert.True(whiteBB8A:getColor8() == whiteBB8)
          assert.True(whiteBB8A:getColor8A() == whiteBB8A)
          assert.True(whiteBB8A:getColor4L() == whiteBB4L)
          assert.True(whiteBB8A:getColor4U() == whiteBB4U)
        end)
        it("from BB8A with alpha 0xFF", function()
          assert.True(whiteBB8Aa:getColorRGB32() == whiteRGB32a)
          assert.True(whiteBB8Aa:getColorRGB24() == whiteRGB24)
          assert.True(whiteBB8Aa:getColorRGB16() == whiteRGB16)
          assert.True(whiteBB8Aa:getColor8() == whiteBB8)
          assert.True(whiteBB8Aa:getColor8A() == whiteBB8Aa)
          assert.True(whiteBB8Aa:getColor4L() == whiteBB4L)
          assert.True(whiteBB8Aa:getColor4U() == whiteBB4U)
        end)
        it("from BB8", function()
          assert.True(whiteBB8:getColorRGB32() == whiteRGB32a)
          assert.True(whiteBB8:getColorRGB24() == whiteRGB24)
          assert.True(whiteBB8:getColorRGB16() == whiteRGB16)
          assert.True(whiteBB8:getColor8() == whiteBB8)
          assert.True(whiteBB8:getColor8A() == whiteBB8Aa)
          assert.True(whiteBB8:getColor4L() == whiteBB4L)
          assert.True(whiteBB8:getColor4U() == whiteBB4U)
        end)
        it("from BB4L", function()
          assert.True(whiteBB4L:getColorRGB32() == whiteRGB32a)
          assert.True(whiteBB4L:getColorRGB24() == whiteRGB24)
          assert.True(whiteBB4L:getColorRGB16() == whiteRGB16)
          assert.True(whiteBB4L:getColor8() == whiteBB8)
          assert.True(whiteBB4L:getColor8A() == whiteBB8Aa)
          assert.True(whiteBB4L:getColor4L() == whiteBB4L)
          assert.True(whiteBB4L:getColor4U() == whiteBB4U)
        end)
        it("from BB4U", function()
          assert.True(whiteBB4U:getColorRGB32() == whiteRGB32a)
          assert.True(whiteBB4U:getColorRGB24() == whiteRGB24)
          assert.True(whiteBB4U:getColorRGB16() == whiteRGB16)
          assert.True(whiteBB4U:getColor8() == whiteBB8)
          assert.True(whiteBB4U:getColor8A() == whiteBB8Aa)
          assert.True(whiteBB4U:getColor4U() == whiteBB4U)
          assert.True(whiteBB4U:getColor4U() == whiteBB4U)
        end)
      end
    )

    describe(
      "should have pure black stay pure black when converting",
      function()
        it("from RGB32 with alpha 0x00", function()
          assert.True(blackRGB32:getColorRGB32() == blackRGB32)
          assert.True(blackRGB32:getColorRGB24() == blackRGB24)
          assert.True(blackRGB32:getColorRGB16() == blackRGB16)
          assert.True(blackRGB32:getColor8() == blackBB8)
          assert.True(blackRGB32:getColor8A() == blackBB8A)
          assert.True(blackRGB32:getColor4L() == blackBB4L)
          assert.True(blackRGB32:getColor4U() == blackBB4U)
        end)
        it("from RGB32 with alpha 0xFF", function()
          assert.True(blackRGB32a:getColorRGB32() == blackRGB32a)
          assert.True(blackRGB32a:getColorRGB24() == blackRGB24)
          assert.True(blackRGB32a:getColorRGB16() == blackRGB16)
          assert.True(blackRGB32a:getColor8() == blackBB8)
          assert.True(blackRGB32a:getColor8A() == blackBB8Aa)
          assert.True(blackRGB32a:getColor4L() == blackBB4L)
          assert.True(blackRGB32a:getColor4U() == blackBB4U)
        end)
        it("from RGB24", function()
          assert.True(blackRGB24:getColorRGB32() == blackRGB32a)
          assert.True(blackRGB24:getColorRGB24() == blackRGB24)
          assert.True(blackRGB24:getColorRGB16() == blackRGB16)
          assert.True(blackRGB24:getColor8() == blackBB8)
          assert.True(blackRGB24:getColor8A() == blackBB8Aa)
          assert.True(blackRGB24:getColor4L() == blackBB4L)
          assert.True(blackRGB24:getColor4U() == blackBB4U)
        end)
        it("from RGB16", function()
          assert.True(blackRGB16:getColorRGB32() == blackRGB32a)
          assert.True(blackRGB16:getColorRGB24() == blackRGB24)
          assert.True(blackRGB16:getColorRGB16() == blackRGB16)
          assert.True(blackRGB16:getColor8() == blackBB8)
          assert.True(blackRGB16:getColor8A() == blackBB8Aa)
          assert.True(blackRGB16:getColor4L() == blackBB4L)
          assert.True(blackRGB16:getColor4U() == blackBB4U)
        end)
        it("from BB8A", function()
          assert.True(blackBB8A:getColorRGB32() == blackRGB32)
          assert.True(blackBB8A:getColorRGB24() == blackRGB24)
          assert.True(blackBB8A:getColorRGB16() == blackRGB16)
          assert.True(blackBB8A:getColor8() == blackBB8)
          assert.True(blackBB8A:getColor8A() == blackBB8A)
          assert.True(blackBB8A:getColor4L() == blackBB4L)
          assert.True(blackBB8A:getColor4U() == blackBB4U)
        end)
        it("from BB8", function()
          assert.True(blackBB8:getColorRGB32() == blackRGB32a)
          assert.True(blackBB8:getColorRGB24() == blackRGB24)
          assert.True(blackBB8:getColorRGB16() == blackRGB16)
          assert.True(blackBB8:getColor8() == blackBB8)
          assert.True(blackBB8:getColor8A() == blackBB8Aa)
          assert.True(blackBB8:getColor4L() == blackBB4L)
          assert.True(blackBB8:getColor4U() == blackBB4U)
        end)
        it("from BB4L", function()
          assert.True(blackBB4L:getColorRGB32() == blackRGB32a)
          assert.True(blackBB4L:getColorRGB24() == blackRGB24)
          assert.True(blackBB4L:getColorRGB16() == blackRGB16)
          assert.True(blackBB4L:getColor8() == blackBB8)
          assert.True(blackBB4L:getColor8A() == blackBB8Aa)
          assert.True(blackBB4L:getColor4L() == blackBB4L)
          assert.True(blackBB4L:getColor4U() == blackBB4U)
        end)
        it("from BB4U", function()
          assert.True(blackBB4U:getColorRGB32() == blackRGB32a)
          assert.True(blackBB4U:getColorRGB24() == blackRGB24)
          assert.True(blackBB4U:getColorRGB16() == blackRGB16)
          assert.True(blackBB4U:getColor8() == blackBB8)
          assert.True(blackBB4U:getColor8A() == blackBB8Aa)
          assert.True(blackBB4U:getColor4U() == blackBB4U)
          assert.True(blackBB4U:getColor4U() == blackBB4U)
        end)
      end
    )

    describe(
      "should have non-pure white stay non-pure white when converting",
      function()
        it("from RGB32", function()
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFE, 0x00):getColorRGB32()
              ~= whiteRGB32
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFE, 0xFF, 0x00):getColorRGB32()
              ~= whiteRGB32
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFE, 0xFF, 0xFF, 0x00):getColorRGB32()
              ~= whiteRGB32
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFE, 0x00):getColorRGB24()
              ~= whiteRGB24
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFE, 0xFF, 0x00):getColorRGB24()
              ~= whiteRGB24
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFE, 0xFF, 0xFF, 0x00):getColorRGB24()
              ~= whiteRGB24
          )
          -- These ones do fail and may (or not) need fixing (the simple conversion
          -- method take the most significant bits, so it misses the one we change)
          -- assert.True(Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFE, 0x00):getColorRGB16() ~= whiteRGB16)
          -- assert.True(Blitbuffer.ColorRGB32(0xFF, 0xFE, 0xFF, 0x00):getColorRGB16() ~= whiteRGB16)
          -- assert.True(Blitbuffer.ColorRGB32(0xFE, 0xFF, 0xFF, 0x00):getColorRGB16() ~= whiteRGB16)
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFE, 0x00):getColor8()
              ~= whiteBB8
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFE, 0xFF, 0x00):getColor8()
              ~= whiteBB8
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFE, 0xFF, 0xFF, 0x00):getColor8()
              ~= whiteBB8
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFF, 0xFE, 0xFF):getColor8A()
              ~= whiteBB8A
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFF, 0xFE, 0xFF, 0xFF):getColor8A()
              ~= whiteBB8A
          )
          assert.True(
            Blitbuffer.ColorRGB32(0xFE, 0xFF, 0xFF, 0xFF):getColor8A()
              ~= whiteBB8A
          )
        end)

        -- RGB24 should use the same rules than RGB32, no need to check

        it("from RGB16", function()
          -- hex((31<<11)+(63<<5)+31) = '0xffff' = pure white
          -- hex((30<<11)+(63<<5)+31) = '0xf7ff'
          -- hex((31<<11)+(62<<5)+31) = '0xffdf'
          -- hex((31<<11)+(63<<5)+30) = '0xfffe'
          assert.True(
            Blitbuffer.ColorRGB16(0xF7FF):getColorRGB16() ~= whiteRGB16
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFDF):getColorRGB16() ~= whiteRGB16
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFFE):getColorRGB16() ~= whiteRGB16
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xF7FF):getColorRGB24() ~= whiteRGB24
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFDF):getColorRGB24() ~= whiteRGB24
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFFE):getColorRGB24() ~= whiteRGB24
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xF7FF):getColorRGB16() ~= whiteRGB16
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFDF):getColorRGB16() ~= whiteRGB16
          )
          assert.True(
            Blitbuffer.ColorRGB16(0xFFFE):getColorRGB16() ~= whiteRGB16
          )
          assert.True(Blitbuffer.ColorRGB16(0xF7FF):getColor8() ~= whiteBB8)
          assert.True(Blitbuffer.ColorRGB16(0xFFDF):getColor8() ~= whiteBB8)
          assert.True(Blitbuffer.ColorRGB16(0xFFFE):getColor8() ~= whiteBB8)
          assert.True(Blitbuffer.ColorRGB16(0xF7FF):getColor8A() ~= whiteBB8A)
          assert.True(Blitbuffer.ColorRGB16(0xFFDF):getColor8A() ~= whiteBB8A)
          assert.True(Blitbuffer.ColorRGB16(0xFFFE):getColor8A() ~= whiteBB8A)
        end)

        it("from BB8", function()
          assert.True(Blitbuffer.Color8(0xFE):getColorRGB32() ~= whiteRGB32a)
          assert.True(Blitbuffer.Color8(0xFE):getColorRGB24() ~= whiteRGB24)
          -- This one does fail and may (or not) need fixing (the simple conversion method
          -- does some rshift then lshift, the bit we changed is lost in the process)
          -- assert.True(Blitbuffer.Color8(0xFE):getColorRGB16() ~= whiteRGB16)
          assert.True(Blitbuffer.Color8(0xFE):getColor8() ~= whiteBB8)
          assert.True(Blitbuffer.Color8(0xFE):getColor8A() ~= whiteBB8A)
        end)
      end
    )
  end)

  describe("basic BB API", function()
    it("should create new buffer with correct width and length", function()
      local bb = Blitbuffer.new(100, 200)
      assert.are_not.equals(bb, nil)
      assert.are.equals(bb:getWidth(), 100)
      assert.are.equals(bb:getHeight(), 200)
    end)

    it("should set pixel correctly", function()
      local bb = Blitbuffer.new(800, 600, Blitbuffer.TYPE_BB4)
      local test_x = 15
      local test_y = 20
      local new_c = Blitbuffer.Color4(2)
      assert.are_not.equals(bb:getPixel(test_x, test_y)["a"], new_c["a"])
      bb:setPixel(test_x, test_y, new_c)
      assert.are.equals(bb:getPixel(test_x, test_y)["a"], new_c["a"])
    end)

    it("should do color comparison correctly", function()
      assert.True(Blitbuffer.Color4(122) == Blitbuffer.Color4(122))
      assert.True(Blitbuffer.Color4L(122) == Blitbuffer.Color4L(122))
      assert.True(Blitbuffer.Color4U(123) == Blitbuffer.Color4U(123))
      assert.True(Blitbuffer.Color8(127) == Blitbuffer.Color8(127))
      assert.True(
        Blitbuffer.ColorRGB24(128, 125, 123)
          == Blitbuffer.ColorRGB24(128, 125, 123)
      )
      assert.True(
        Blitbuffer.ColorRGB32(128, 120, 123, 1)
          == Blitbuffer.ColorRGB32(128, 120, 123, 1)
      )
    end)

    it("should do color comparison with conversion correctly", function()
      assert.True(
        Blitbuffer.Color8(127) == Blitbuffer.ColorRGB24(127, 127, 127)
      )
      assert.True(
        Blitbuffer.Color8A(127, 100)
          == Blitbuffer.ColorRGB32(127, 127, 127, 100)
      )
    end)

    it("should do color blending correctly", function()
      -- opaque
      local c = Blitbuffer.Color8(100)
      c:blend(Blitbuffer.Color8(200))
      assert.True(c == Blitbuffer.Color8(200))
      c = Blitbuffer.Color4U(0)
      c:blend(Blitbuffer.Color4U(4))
      assert.True(c == Blitbuffer.Color4U(4))
      c = Blitbuffer.Color4L(10)
      c:blend(Blitbuffer.Color4L(0))
      assert.True(c == Blitbuffer.Color4L(0))
      -- alpha
      c = Blitbuffer.Color8(100)
      c:blend(Blitbuffer.Color8A(200, 127))
      assert.True(c == Blitbuffer.Color8(150))
      c = Blitbuffer.ColorRGB32(50, 100, 200, 255)
      c:blend(Blitbuffer.ColorRGB32(200, 127, 50, 127))
      assert.True(c == Blitbuffer.ColorRGB32(125, 113, 125, 255))
      -- premultiplied alpha
      c = Blitbuffer.Color8(100)
      c:pmulblend(Blitbuffer.Color8A(100, 127))
      assert.True(c == Blitbuffer.Color8(150))
      c = Blitbuffer.ColorRGB32(50, 100, 200, 255)
      c:pmulblend(Blitbuffer.ColorRGB32(100, 63, 25, 127))
      assert.True(c == Blitbuffer.ColorRGB32(125, 113, 125, 255))
    end)

    it("should scale blitbuffer correctly", function()
      local bb = Blitbuffer.new(100, 100, Blitbuffer.TYPE_BBRGB24)
      local test_c1 = Blitbuffer.ColorRGB24(255, 128, 0)
      local test_c2 = Blitbuffer.ColorRGB24(128, 128, 0)
      local test_c3 = Blitbuffer.ColorRGB24(0, 128, 0)
      bb:setPixel(0, 0, test_c1)
      bb:setPixel(1, 0, test_c2)
      bb:setPixel(2, 0, test_c3)

      local scaled_bb = bb:scale(200, 200)
      assert.are.equals(scaled_bb:getWidth(), 200)
      assert.are.equals(scaled_bb:getHeight(), 200)
      assert.True(test_c1 == scaled_bb:getPixel(0, 0))
      assert.True(test_c1 == scaled_bb:getPixel(0, 1))
      assert.True(test_c1 == scaled_bb:getPixel(1, 0))
      assert.True(test_c1 == scaled_bb:getPixel(1, 1))

      assert.True(test_c2 == scaled_bb:getPixel(2, 0))
      assert.True(test_c2 == scaled_bb:getPixel(3, 0))
      assert.True(test_c2 == scaled_bb:getPixel(2, 1))
      assert.True(test_c2 == scaled_bb:getPixel(3, 1))

      scaled_bb = bb:scale(50, 50)
      assert.are.equals(scaled_bb:getWidth(), 50)
      assert.are.equals(scaled_bb:getHeight(), 50)

      assert.True(test_c1 == scaled_bb:getPixel(0, 0))
      assert.True(test_c3 == scaled_bb:getPixel(1, 0))
    end)

    it("should blit correctly", function()
      local bb1 = Blitbuffer.new(100, 100, Blitbuffer.TYPE_BBRGB24)
      local test_c1 = Blitbuffer.ColorRGB24(255, 128, 0)
      local test_c2 = Blitbuffer.ColorRGB24(128, 128, 0)
      local test_c3 = Blitbuffer.ColorRGB24(0, 128, 0)
      bb1:setPixel(0, 0, test_c1)
      bb1:setPixel(1, 0, test_c2)
      bb1:setPixel(2, 0, test_c3)
      assert.True(test_c1 == bb1:getPixel(0, 0))
      assert.True(test_c2 == bb1:getPixel(1, 0))
      assert.True(test_c3 == bb1:getPixel(2, 0))

      local test_c4 = Blitbuffer.ColorRGB24(0, 0, 0)
      local bb2 = Blitbuffer.new(100, 100, Blitbuffer.TYPE_BBRGB24)
      assert.True(test_c4 == bb2:getPixel(0, 0))
      assert.True(test_c4 == bb2:getPixel(1, 0))
      assert.True(test_c4 == bb2:getPixel(2, 0))

      bb2:addblitFrom(bb1, 0, 0, 0, 0, 100, 100, 1)
      assert.True(test_c1 == bb2:getPixel(0, 0))
      assert.True(test_c2 == bb2:getPixel(1, 0))
      assert.True(test_c3 == bb2:getPixel(2, 0))
    end)
  end)

  describe("BB rotation functionality", function()
    it("should get physical rect in all rotation modes", function()
      local bb = Blitbuffer.new(600, 800)
      bb:setRotation(0)
      assert.are_same(
        { 50, 100, 150, 200 },
        { bb:getPhysicalRect(50, 100, 150, 200) }
      )
      bb:setRotation(1)
      assert.are_same(
        { 50, 100, 150, 200 },
        { bb:getPhysicalRect(100, 400, 200, 150) }
      )
      bb:setRotation(2)
      assert.are_same(
        { 50, 100, 150, 200 },
        { bb:getPhysicalRect(400, 500, 150, 200) }
      )
      bb:setRotation(3)
      assert.are_same(
        { 50, 100, 150, 200 },
        { bb:getPhysicalRect(500, 50, 200, 150) }
      )
    end)

    it("should set pixel in all rotation modes", function()
      local width, height = 100, 200
      for rotation = 0, 3 do
        local bb = Blitbuffer.new(width, height)
        bb:setRotation(rotation)
        local w = rotation % 2 == 1 and height or width
        local h = rotation % 2 == 1 and width or height
        for i = 0, (h - 1) do
          for j = 0, (w - 1) do
            local color = Blitbuffer.Color4(2)
            assert.are_not_same(color.a, bb:getPixel(j, i):getColor4L().a)
            bb:setPixel(j, i, color)
            assert.are_same(color.a, bb:getPixel(j, i):getColor4L().a)
          end
        end
      end
    end)
  end)
end)
