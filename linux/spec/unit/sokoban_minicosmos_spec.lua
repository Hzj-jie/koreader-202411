describe("Sokoban Minicosmos levels data module", function()
  local Levels

  setup(function()
    require("commonrequire")
    Levels = require("plugins/sokoban.koplugin/levels/minicosmos")
  end)

  it("should return minicosmos levels table", function()
    assert.is_table(Levels)
  end)
end)
