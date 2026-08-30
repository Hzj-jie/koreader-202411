describe("Sokoban Microcosmos levels data module", function()
  local Levels

  setup(function()
    require("commonrequire")
    Levels = require("plugins/sokoban.koplugin/levels/microcosmos")
  end)

  it("should return microcosmos levels table", function()
    assert.is_table(Levels)
  end)
end)
