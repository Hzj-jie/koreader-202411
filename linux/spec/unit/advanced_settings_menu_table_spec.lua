describe("AdvancedSettingsMenuTable element", function()
  local AdvancedSettingsMenuTable

  setup(function()
    require("commonrequire")
    AdvancedSettingsMenuTable = require("ui/elements/advanced_settings_menu_table")
  end)

  it("should return advanced settings menu table", function()
    assert.is_table(AdvancedSettingsMenuTable)
    assert.is_string(AdvancedSettingsMenuTable.text)
  end)
end)
