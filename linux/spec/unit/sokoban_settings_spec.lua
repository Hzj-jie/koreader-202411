describe("SokobanSettings module", function()
  local Settings

  setup(function()
    require("commonrequire")
    Settings = require("plugins/sokoban.koplugin/sokoban_settings")
  end)

  it("should expose Settings table for Sokoban plugin", function()
    assert.is_table(Settings)
  end)
end)
