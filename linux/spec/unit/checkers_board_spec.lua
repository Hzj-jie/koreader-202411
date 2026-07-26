describe("Checkers Board widget module", function()
  local Board, Game

  setup(function()
    require("commonrequire")
    Board = require("plugins/checkers.koplugin/board")
    Game = require("plugins/checkers.koplugin/game")
  end)

  it("should initialize Checkers Board widget instance", function()
    local game = Game:new()
    local board = Board:new({
      game = game,
      width = 400,
      height = 400,
    })

    assert.is_table(board)
    if type(board.clearSelection) == "function" then
      board:clearSelection()
    end
  end)
end)
