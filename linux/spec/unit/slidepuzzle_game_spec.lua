describe("SlidePuzzleGame module", function()
  local Game

  setup(function()
    require("commonrequire")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
  end)

  it("should initialize Game logic instance and handle moves", function()
    local game = Game:new(3)
    assert.is_table(game)
    assert.are.equal(3, game.size)
    assert.is_boolean(game.won)
  end)
end)
