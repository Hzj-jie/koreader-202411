describe("SokobanBoard widget", function()
  local BoardWidget, SokobanGame

  setup(function()
    require("commonrequire")
    BoardWidget = require("plugins/sokoban.koplugin/sokoban_board")
    SokobanGame = require("plugins/sokoban.koplugin/sokoban_game")
  end)

  it("should initialize BoardWidget", function()
    local xsb = "#####\n#@ $.#\n#####"
    local game = SokobanGame.from_xsb(xsb)
    local board = BoardWidget:new({
      game = game,
      width = 400,
      height = 400,
    })
    assert.is_table(board)
  end)
end)
