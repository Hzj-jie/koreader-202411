describe("SlidePuzzleSettings module", function()
  local Settings

  setup(function()
    require("commonrequire")
    Settings = require("plugins/slidepuzzle.koplugin/slidepuzzle_settings")
  end)

  it("should expose Settings helper functions", function()
    assert.is_table(Settings)
  end)
end)
