describe("Checkers plugin Game logic module", function()
  local Game

  setup(function()
    require("commonrequire")
    Game = require("plugins/checkers.koplugin/game")
  end)

  it("should initialize Checkers Game instance", function()
    local game = Game:new()
    assert.is_table(game)
  end)
end)
