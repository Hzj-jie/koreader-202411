describe("OptionsUtil module", function()
  local OptionsUtil

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    OptionsUtil = require("ui/data/optionsutil")
  end)

  it("should expose optionsutil table and rotation constants", function()
    assert.is_table(OptionsUtil)
    assert.is_table(OptionsUtil.rotation_labels)
    assert.is_table(OptionsUtil.rotation_modes)
    assert.is_same(4, #OptionsUtil.rotation_labels)
  end)

  it("should evaluate enableIfEquals correctly", function()
    local configurable = { option1 = "val1", option2 = "val2" }
    assert.is_true(OptionsUtil.enableIfEquals(configurable, "option1", "val1"))
    assert.is_false(OptionsUtil.enableIfEquals(configurable, "option1", "val2"))
  end)

  it("should format flex size string across different units", function()
    local formatted_pt = OptionsUtil.formatFlexSize(12, "pt")
    assert.is_string(formatted_pt)

    local formatted_mm = OptionsUtil.formatFlexSize(10, "mm")
    assert.is_string(formatted_mm)

    local formatted_px = OptionsUtil.formatFlexSize(100, "px")
    assert.is_string(formatted_px)
  end)

  it("should show values and margin information dialogs", function()
    local configurable = {
      font_size = 12,
      margin = { 10, 10 },
    }
    local option = {
      name = "font_size",
      name_text = "Font Size",
    }
    local margin_option = {
      name = "margin",
    }

    OptionsUtil.showValues(configurable, option, "copt", nil, "pt")
    OptionsUtil.showValuesHMargins(configurable, margin_option)
  end)

  it("should generate and retrieve option text by event and value", function()
    OptionsUtil:generateOptionText()
    local text = OptionsUtil:getOptionText("NonExistentEvent", 1)
    assert.are.equal("", text)
  end)
end)
