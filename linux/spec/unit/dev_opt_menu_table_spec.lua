describe("DevOptMenuTable element", function()
  local DevOptMenuTable

  setup(function()
    require("commonrequire")
    DevOptMenuTable = require("ui/elements/dev_opt_menu_table")
  end)

  it("should return a valid developer menu options table", function()
    assert.is_table(DevOptMenuTable)
    assert.is_string(DevOptMenuTable.text)
  end)
end)
