describe("OptionsUtil module", function()
  local OptionsUtil

  setup(function()
    require("commonrequire")
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
end)
