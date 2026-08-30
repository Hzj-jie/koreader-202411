describe("Checkers AI module", function()
  local AI, Game

  setup(function()
    require("commonrequire")
    AI = require("plugins/checkers.koplugin/ai")
    Game = require("plugins/checkers.koplugin/game")
  end)

  it("should evaluate best move for Checkers game state", function()
    local game = Game:new()
    local move = AI.best_move(game, 1)
    assert.is_table(move)
  end)
end)
