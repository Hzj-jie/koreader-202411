describe("Game2048Config module", function()
  local Game2048Config

  setup(function()
    require("commonrequire")
    Game2048Config = require("plugins/game2048.koplugin/modules/game2048config")
  end)

  it("should initialize Game2048Config", function()
    local config = Game2048Config:new()
    assert.is_table(config)
  end)
end)
