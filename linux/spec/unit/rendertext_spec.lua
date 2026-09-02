describe("RenderText", function()
  local RenderText
  local Font
  local Blitbuffer

  setup(function()
    require("commonrequire")
    RenderText = require("ui/rendertext")
    Font = require("ui/font")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should get glyph and cache it", function()
    local face = Font:getFace("infofont", 14)
    local glyph1 = RenderText:getGlyph(face, string.byte("A"), false)
    assert.truthy(glyph1)
    assert.truthy(glyph1.bb)
    assert.is_number(glyph1.ax)

    -- Cache hit
    local glyph2 = RenderText:getGlyph(face, string.byte("A"), false)
    assert.are.equal(glyph1, glyph2)

    -- Bold glyph
    local glyph_bold = RenderText:getGlyph(face, string.byte("A"), true)
    assert.truthy(glyph_bold)
  end)

  it("should fallback to fallback font if glyph is missing in primary face", function()
    local face = Font:getFace("infofont", 14)
    -- Chinese character: 你 (0x4F60)
    local glyph = RenderText:getGlyph(face, 0x4F60, false)
    -- Should resolve via fallback fonts or handle gracefully
    assert.truthy(glyph)
  end)

  it("should measure text size with sizeUtf8Text", function()
    local face = Font:getFace("infofont", 14)
    local size = RenderText:sizeUtf8Text(0, 500, face, "Hello World! 123", true, false)
    assert.truthy(size)
    assert.is_true(size.x > 0)
    assert.is_true(size.y_top >= 0)
    assert.is_true(size.y_bottom >= 0)

    -- nil text handling
    local nil_size = RenderText:sizeUtf8Text(0, 500, face, nil, true, false)
    assert.are.same({ x = 0, y_top = 0, y_bottom = 0 }, nil_size)
  end)

  it("should get subtext by width and truncate text with ellipsis", function()
    local face = Font:getFace("infofont", 14)
    local full_text = "The quick brown fox jumps over the lazy dog"

    local subtext = RenderText:getSubTextByWidth(full_text, face, 60, true, false)
    assert.truthy(subtext)
    assert.is_true(#subtext < #full_text)

    local ell_width = RenderText:getEllipsisWidth(face)
    assert.is_true(ell_width > 0)

    local truncated = RenderText:truncateTextByWidth(full_text, face, 60, true, false)
    assert.truthy(truncated)
    assert.truthy(truncated:find("…"))
  end)

  it("should render UTF8 text into a BlitBuffer including char_pads", function()
    local face = Font:getFace("infofont", 14)
    local bb = Blitbuffer.new(300, 50)

    local width = RenderText:renderUtf8Text(
      bb,
      10,
      30,
      face,
      "Test string",
      true,
      false,
      Blitbuffer.COLOR_BLACK,
      250,
      { 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2 }
    )
    assert.is_true(width > 0)

    -- nil text handling
    local zero_w = RenderText:renderUtf8Text(bb, 0, 0, face, nil)
    assert.are.equal(0, zero_w)

    bb:free()
  end)

  it("should handle multi-byte and invalid UTF8 byte sequences", function()
    local face = Font:getFace("infofont", 14)
    -- Valid 2-byte, 3-byte, 4-byte characters
    local mixed_text = "é (€) 𠜎"
    local size = RenderText:sizeUtf8Text(0, 500, face, mixed_text, false, false)
    assert.is_true(size.x > 0)

    -- Invalid byte sequences (continuation byte alone, truncated multi-byte, 5-byte sequence)
    local invalid_text = "\x80\xFF\xC0\x20\xE0\x80\xF0\x80\x80\xF8\x80"
    local inv_size = RenderText:sizeUtf8Text(0, 500, face, invalid_text, false, false)
    assert.truthy(inv_size)
  end)

  it("should get glyph by index with bold and bolder strengths", function()
    local face = Font:getFace("infofont", 14)
    local glyph = RenderText:getGlyphByIndex(face, 10, false, false)
    assert.truthy(glyph)

    local glyph_bold = RenderText:getGlyphByIndex(face, 10, true, false)
    assert.truthy(glyph_bold)

    local glyph_bolder = RenderText:getGlyphByIndex(face, 10, false, true)
    assert.truthy(glyph_bolder)
  end)
end)
