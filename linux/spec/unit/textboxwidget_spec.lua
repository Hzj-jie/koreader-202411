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
end)
