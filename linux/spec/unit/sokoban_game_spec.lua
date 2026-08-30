describe("SokobanGame module", function()
  local SokobanGame

  setup(function()
    require("commonrequire")
    SokobanGame = require("plugins/sokoban.koplugin/sokoban_game")
  end)

  it("should initialize SokobanGame instance from XSB string", function()
    local xsb = "#####\n#@ $.#\n#####"
    local game = SokobanGame.from_xsb(xsb)
    assert.is_table(game)
    assert.are.equal(SokobanGame.PLAYER, game.grid[2][2])
  end)
end)
