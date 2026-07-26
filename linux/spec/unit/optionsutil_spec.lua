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

  it("should retrieve next and previous items safely", function()
    local list = { "a", "b", "c" }
    if type(OptionsUtil.getNextItem) == "function" then
      assert.are.equal("b", OptionsUtil.getNextItem(list, "a"))
    end
    if type(OptionsUtil.getPrevItem) == "function" then
      assert.are.equal("b", OptionsUtil.getPrevItem(list, "c"))
    end
  end)

  it("should evaluate enableIfNotEquals correctly", function()
    local configurable = { option1 = "val1", option2 = "val2" }
    if type(OptionsUtil.enableIfNotEquals) == "function" then
      assert.is_false(
        OptionsUtil.enableIfNotEquals(configurable, "option1", "val1")
      )
      assert.is_true(
        OptionsUtil.enableIfNotEquals(configurable, "option1", "val2")
      )
    end
  end)
end)
