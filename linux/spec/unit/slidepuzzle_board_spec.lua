describe("SlidePuzzleBoard widget", function()
  local BoardWidget, Game

  setup(function()
    require("commonrequire")
    BoardWidget = require("plugins/slidepuzzle.koplugin/slidepuzzle_board")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
  end)

  it("should initialize BoardWidget", function()
    local game = Game:new(3)
    local board = BoardWidget:new({
      game = game,
    })
    assert.is_table(board)
  end)
end)
