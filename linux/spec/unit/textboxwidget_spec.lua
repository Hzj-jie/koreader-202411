describe("TextBoxWidget widget", function()
  require("commonrequire")
  local TextBoxWidget = require("ui/widget/textboxwidget")
  local Font = require("ui/font")

  setup(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it("should wrap text correctly and detect holds", function()
    local tw = TextBoxWidget:new({
      dimen = { x = 0, y = 0 },
      face = Font:getFace("cfont", 25),
      text = "Foo welcomes Bar into the fun.",
    })
    tw:onHoldStartText(nil, { pos = { x = 50, y = 10 } })
    tw:onHoldReleaseText(function(w)
      assert.is.same(w, "welcomes Bar into")
    end, { pos = { x = 240, y = 10 } })

    -- Test multiline wrapping
    tw = TextBoxWidget:new({
      dimen = { x = 0, y = 0 },
      face = Font:getFace("cfont", 25),
      text = "Foo welcomes Bar into\nthe fun.",
    })
    tw:onHoldStartText(nil, { pos = { x = 240, y = 10 } })
    tw:onHoldReleaseText(function(w)
      assert.is.same(w, "Bar.\nFoo welcomes Bar into")
    end, { pos = { x = 240, y = 100 } })
  end)

  it(
    "should handle nil face gracefully by falling back to default face",
    function()
      local tw
      assert.has_no.errors(function()
        tw = TextBoxWidget:new({
          dimen = { x = 0, y = 0 },
          text = "Hello World",
        })
      end)
      assert.is_not_nil(tw.face)
      assert.are.equal(tw.face.realname, Font.fontmap.cfont)
    end
  )

  it(
    "should set and clear selection indexes on drag/pan and release",
    function()
      local tw = TextBoxWidget:new({
        dimen = { x = 0, y = 0 },
        face = Font:getFace("cfont", 25),
        text = "Foo welcomes Bar into the fun.",
      })

      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)

      -- 1. Start selection
      tw:onHoldStartText(nil, { pos = { x = 50, y = 10 } })
      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)

      -- 2. Drag/Pan to select more text
      tw:onHoldPanText(nil, { pos = { x = 240, y = 10 } })
      assert.is_not_nil(tw.sel_start_idx)
      assert.is_not_nil(tw.sel_end_idx)
      -- Verify that start is before end
      assert.is_true(tw.sel_start_idx < tw.sel_end_idx)

      -- 3. Release selection
      tw:onHoldReleaseText(function(w)
        assert.is.same(w, "welcomes Bar into")
      end, { pos = { x = 240, y = 10 } })

      -- Selection indexes must be cleared after release
      assert.is_nil(tw.sel_start_idx)
      assert.is_nil(tw.sel_end_idx)
    end
  )
  it(
    "should not wrap ls after prompt when no_line_breaking_rules is true",
    function()
      local face = Font:getFace("cfont", 25)
      local text = "welcome\n$ ls" .. string.rep(" ", 16) .. "\n"

      local function getLineText(tw, line_num)
        local line = tw.vertical_string_list[line_num]
        if not line then
          return nil
        end
        local chars = require("util").splitToChars(tw.text)
        local start_idx = line.offset
        local end_idx = line.end_offset or #chars
        local line_text = {}
        for j = start_idx, end_idx do
          table.insert(line_text, chars[j] or "?")
        end
        return table.concat(line_text)
      end

      -- Case 1: use_xtext = true, no_line_breaking_rules = true
      local tw1 = TextBoxWidget:new({
        width = 140,
        face = face,
        text = text,
        use_xtext = true,
        no_line_breaking_rules = true,
      })
      assert.are.equal("welcome", getLineText(tw1, 1))
      local line2_1 = getLineText(tw1, 2)
      assert.is_not_nil(line2_1)
      assert.is_true(line2_1:sub(1, 4) == "$ ls")

      -- Case 2: use_xtext = false, no_line_breaking_rules = true
      local tw2 = TextBoxWidget:new({
        width = 140,
        face = face,
        text = text,
        use_xtext = false,
        no_line_breaking_rules = true,
      })
      assert.are.equal("welcome", getLineText(tw2, 1))
      local line2_2 = getLineText(tw2, 2)
      assert.is_not_nil(line2_2)
      assert.is_true(line2_2:sub(1, 4) == "$ ls")

      -- For comparison, verify that with use_xtext = true, no_line_breaking_rules = false,
      -- it DOES wrap ls (the bug we are fixing)
      local tw3 = TextBoxWidget:new({
        width = 140,
        face = face,
        text = text,
        use_xtext = true,
        no_line_breaking_rules = false,
      })
      assert.are.equal("welcome", getLineText(tw3, 1))
      assert.are.equal("$", getLineText(tw3, 2)) -- only "$" on line 2!
    end
  )

  it("should update text and line count via setText()", function()
    local tw = TextBoxWidget:new({
      dimen = { x = 0, y = 0 },
      face = Font:getFace("cfont", 25),
      text = "Initial Text",
    })
    assert.is_equal("Initial Text", tw.text)

    tw:setText("New Multi\nLine Text")
    assert.is_equal("New Multi\nLine Text", tw.text)
    assert.is_true(#tw.vertical_string_list >= 2)
  end)

  it(
    "should handle moveCursorToCharPos gracefully when virtual_line_num is out of bounds (Issue #478)",
    function()
      local tw = TextBoxWidget:new({
        dimen = { x = 0, y = 0 },
        width = 200,
        height = 100,
        editable = true,
        text = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5",
      })
      tw.virtual_line_num = 5
      tw.text = "A"
      tw.charlist = { "A" }
      tw:_computeTextDimensions()
      tw:update()

      assert.has_no.errors(function()
        tw:_getXYForCharPos(1)
        tw:moveCursorToCharPos(1)
      end)
    end
  )

  it("should handle scrolling operations correctly", function()
    local tw = TextBoxWidget:new({
      width = 200,
      height = 60,
      face = Font:getFace("cfont", 20),
      text = "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8",
    })
    assert.are.equal(1, tw.virtual_line_num)
    local all_lines = tw:getAllLineCount()
    local vis_lines = tw:getVisLineCount()
    assert.is_true(all_lines >= 8)
    assert.is_true(vis_lines >= 1)

    -- Scroll down
    tw:scrollDown()
    assert.is_true(tw.virtual_line_num > 1)

    -- Scroll up
    tw:scrollUp()
    assert.are.equal(1, tw.virtual_line_num)

    -- Scroll lines
    tw:scrollLines(2)
    assert.are.equal(3, tw.virtual_line_num)
    tw:scrollLines(-1)
    assert.are.equal(2, tw.virtual_line_num)

    -- Scroll to bottom and top
    tw:scrollToBottom()
    assert.is_true(tw.virtual_line_num > 1)
    tw:scrollToTop()
    assert.are.equal(1, tw.virtual_line_num)

    -- Scroll to ratio
    tw:scrollToRatio(0.5)
    assert.is_true(tw.virtual_line_num >= 1)

    local low, high = tw:getVisibleHeightRatios()
    assert.is_true(low >= 0 and low <= 1)
    assert.is_true(high >= 0 and high <= 1)
  end)

  it(
    "should calculate dimensions, baselines and font sizes to fit height",
    function()
      local font_size = TextBoxWidget:getFontSizeToFitHeight(100, 4, 0.3)
      assert.is_number(font_size)
      assert.is_true(font_size > 0)

      local tw = TextBoxWidget:new({
        width = 300,
        face = Font:getFace("cfont", 20),
        text = "Short text for measuring dimensions",
      })
      assert.is_number(tw:getTextHeight())
      assert.is_number(tw:getLineHeight())
      assert.is_number(tw:getBaseline())
      assert.is_table(tw:getSize())
      assert.is_number(tw:getSize().w)
      assert.is_number(tw:getSize().h)
    end
  )

  it("should parse Poor Text Formatting (PTF) tags", function()
    local ptf_text = TextBoxWidget.PTF_HEADER
      .. "Hello "
      .. TextBoxWidget.PTF_BOLD_START
      .. "World"
      .. TextBoxWidget.PTF_BOLD_END
      .. "!"
    local tw = TextBoxWidget:new({
      width = 300,
      face = Font:getFace("cfont", 20),
      text = ptf_text,
    })
    assert.are.equal("Hello World!", tw.text)
    assert.is_table(tw._ptf_char_is_bold)
    -- "World" starts at index 7
    assert.is_true(tw._ptf_char_is_bold[7])
    assert.is_true(tw._ptf_char_is_bold[11])
    assert.is_nil(tw._ptf_char_is_bold[1])
  end)

  it("should handle alignments and paintTo without error", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local tw_center = TextBoxWidget:new({
      width = 300,
      alignment = "center",
      face = Font:getFace("cfont", 20),
      text = "Centered text line",
    })
    local tw_right = TextBoxWidget:new({
      width = 300,
      alignment = "right",
      face = Font:getFace("cfont", 20),
      text = "Right aligned line",
    })
    local tw_justified = TextBoxWidget:new({
      width = 300,
      justified = true,
      face = Font:getFace("cfont", 20),
      text = "This is a long sentence meant to be justified across multiple lines when wrapped properly.",
    })

    local bb = Blitbuffer.new(300, 200)
    assert.has_no.errors(function()
      tw_center:paintTo(bb, 0, 0)
      tw_right:paintTo(bb, 0, 0)
      tw_justified:paintTo(bb, 0, 0)
    end)
    bb:free()
  end)

  it("should handle focus, unfocus, and cursor position queries", function()
    local tw = TextBoxWidget:new({
      width = 200,
      height = 100,
      face = Font:getFace("cfont", 20),
      text = "Editable text line 1\nLine 2\nLine 3",
      editable = false,
    })
    assert.is_false(tw.editable)
    tw:focus()
    assert.is_true(tw.editable)
    local pos, vln, cln = tw:getCharPos()
    assert.is_number(pos or 1)
    assert.is_number(vln)
    assert.is_number(cln)

    tw:unfocus()
    assert.is_false(tw.editable)
    tw:onClose()
  end)
end)
