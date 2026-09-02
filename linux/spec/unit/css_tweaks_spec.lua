describe("CssTweaks", function()
  local CssTweaks

  setup(function()
    require("commonrequire")
    CssTweaks = require("ui/data/css_tweaks")
  end)

  it("should have default global style tweaks", function()
    assert.truthy(CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS)
    assert.is_true(CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS["footnote-inpage_epub_smaller"])
    assert.is_true(CssTweaks.DEFAULT_GLOBAL_STYLE_TWEAKS["footnote-inpage_fb2"])
  end)

  it("should validate all style tweaks and execute conflict check functions", function()
    local function checkItem(item)
      if item.id then
        assert.is_string(item.id)
        assert.is_string(item.title)
        assert.is_string(item.css)

        if type(item.conflicts_with) == "function" then
          assert.is_boolean(item.conflicts_with("footnote-inpage_epub"))
          assert.is_boolean(item.conflicts_with("unrelated_id"))
        end

        if type(item.global_conflicts_with) == "function" then
          assert.is_boolean(item.global_conflicts_with("footnote-inpage_epub"))
          assert.is_boolean(item.global_conflicts_with("unrelated_id"))
        end
      end

      for _, sub_item in ipairs(item) do
        if type(sub_item) == "table" then
          checkItem(sub_item)
        end
      end
    end

    for _, category in ipairs(CssTweaks) do
      checkItem(category)
    end
  end)
end)
