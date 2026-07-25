describe("Sokoban extra levels data modules", function()
  local OriginalPlusExtra, Sasquatch

  setup(function()
    require("commonrequire")
    OriginalPlusExtra = require("plugins/sokoban.koplugin/levels/original-plus-extra")
    Sasquatch = require("plugins/sokoban.koplugin/levels/sasquatch")
  end)

  it("should return level tables for original-plus-extra and sasquatch", function()
    assert.is_table(OriginalPlusExtra)
    assert.is_table(Sasquatch)
  end)
end)
