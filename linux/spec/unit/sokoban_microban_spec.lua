describe("Sokoban Microban levels data module", function()
  local Levels

  setup(function()
    require("commonrequire")
    Levels = require("plugins/sokoban.koplugin/levels/microban")
  end)

  it("should return microban levels table", function()
    assert.is_table(Levels)
  end)
end)
