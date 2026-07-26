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

  it("should handle painting board to canvas context safely", function()
    local Screen = require("device").screen
    local game = Game:new()
    local board = Board:new({
      game = game,
      width = 400,
      height = 400,
    })
    if type(board.paintTo) == "function" then
      board:paintTo(Screen.bb, 0, 0)
    end
  end)
end)
