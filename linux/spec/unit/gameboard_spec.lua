describe("Game2048 GameBoard module", function()
  local GameBoard

  setup(function()
    require("commonrequire")
    GameBoard = require("plugins/game2048.koplugin/modules/gameboard")
  end)

  it("should initialize GameBoard matrix", function()
    local board = GameBoard:new({
      size = 4,
    })

    assert.is_table(board)
  end)
end)
