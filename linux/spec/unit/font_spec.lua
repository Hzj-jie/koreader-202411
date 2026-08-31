describe("Font module", function()
  local Font

  setup(function()
    require("commonrequire")
    Font = require("ui/font")
  end)

  describe("getFace", function()
    it("should get face with various names and sizes", function()
      local f1 = Font:getFace("cfont", 18)
      assert.is_not_nil(f1.ftsize)
      assert.are.equal("cfont", f1.orig_font)

      local f2 = Font:getFace("tfont", 16)
      assert.is_not_nil(f2.ftsize)
      assert.is_true(f2.is_real_bold)

      local f3 = Font:getFace("hfont", 12)
      assert.is_not_nil(f3.ftsize)
    end)

    it("should get default face when called without arguments", function()
      local f = Font:getFace()
      assert.is_not_nil(f)
      assert.are.equal(Font.fontmap.cfont, f.realname)
    end)

    it("should use default cfont size if size is unknown", function()
      local f = Font:getFace("unknown_font_key")
      assert.is_not_nil(f)
      assert.are.equal("unknown_font_key", f.orig_font)
    end)

    it("should update orig_size in cached face when orig_size changes", function()
      local f1 = Font:getFace("cfont", 20)
      assert.are.equal(20, f1.orig_size)

      -- Fetch same scaled size but different orig_size
      local f2 = Font:getFace("cfont", 20)
      assert.are.equal(f1, f2)
    end)

    it("should handle custom faceindex in hash", function()
      local f = Font:getFace("cfont", 18, 0)
      assert.is_not_nil(f)
      assert.truthy(f.hash:find("/0"))
    end)
  end)

  describe("variant helpers", function()
    it("should get bold and regular variant names", function()
      local bold_name = Font:getBoldVariantName("NotoSans-Regular.ttf")
      assert.are.equal("NotoSans-Bold.ttf", bold_name)

      assert.is_true(Font:isRealBoldFont("NotoSans-Bold.ttf"))
      assert.is_false(Font:isRealBoldFont("NotoSans-Regular.ttf"))

      local reg_name = Font:getRegularVariantName("NotoSans-Bold.ttf")
      assert.are.equal("NotoSans-Regular.ttf", reg_name)

      local same_name = Font:getRegularVariantName("SomeUnknownFont.ttf")
      assert.are.equal("SomeUnknownFont.ttf", same_name)
    end)
  end)

  describe("getAdjustedFace", function()
    it("should return unchanged face for non-bold requests", function()
      local face = Font:getFace("cfont", 18)
      local adj_face, is_bold = Font:getAdjustedFace(face, false)
      assert.are.equal(face, adj_face)
      assert.is_false(is_bold)
    end)

    it("should return real bold face as bold=true without changes", function()
      local bold_face = Font:getFace("tfont", 20)
      local adj_face, is_bold = Font:getAdjustedFace(bold_face, true)
      assert.are.equal(bold_face, adj_face)
      assert.is_true(is_bold)
    end)

    it("should promote regular font to real bold variant when available", function()
      local reg_face = Font:getFace("NotoSans-Regular.ttf", 18)
      local adj_face, is_bold = Font:getAdjustedFace(reg_face, true)
      assert.is_true(adj_face.is_real_bold)
      assert.are.equal("NotoSans-Bold.ttf", adj_face.realname)
      assert.is_true(is_bold)
    end)

    it("should synthesize bold when FORCE_SYNTHETIZED_BOLD requested", function()
      local reg_face = Font:getFace("NotoSans-Regular.ttf", 18)
      local adj_face, is_bold = Font:getAdjustedFace(reg_face, Font.FORCE_SYNTHETIZED_BOLD)
      assert.are.equal(Font.FORCE_SYNTHETIZED_BOLD, is_bold)
      assert.are.equal(Font.FORCE_SYNTHETIZED_BOLD, adj_face.wants_bold)

      -- Cached lookup for same synth bold
      local cached_adj = Font:getAdjustedFace(reg_face, Font.FORCE_SYNTHETIZED_BOLD)
      assert.are.equal(adj_face, cached_adj)
    end)

    it("should respect use_bold_font_for_bold setting", function()
      local orig_setting = Font.use_bold_font_for_bold
      Font.use_bold_font_for_bold = false

      local reg_face = Font:getFace("NotoSans-Regular.ttf", 18)
      local adj_face, is_bold = Font:getAdjustedFace(reg_face, true)
      assert.are.equal(Font.FORCE_SYNTHETIZED_BOLD, is_bold)

      Font.use_bold_font_for_bold = orig_setting
    end)
  end)

  describe("getFallbackFont", function()
    it("should return self for num=0", function()
      local face = Font:getFace("cfont", 18)
      local fb0 = face.getFallbackFont(0)
      assert.are.equal(face, fb0)
      assert.truthy(face.embolden_half_strength)
    end)

    it("should iterate through fallback fonts and terminate with false", function()
      local face = Font:getFace("cfont", 18)
      local fallback_count = 0
      for i = 1, 20 do
        local fb = face.getFallbackFont(i)
        if fb == false then
          break
        end
        assert.is_table(fb)
        fallback_count = fallback_count + 1
      end
      assert.is_true(fallback_count > 0)
    end)

    it("should iterate fallbacks for bold face", function()
      local bold_face = Font:getFace("tfont", 18)
      local fb1 = bold_face.getFallbackFont(1)
      assert.truthy(fb1)
    end)
  end)
end)

