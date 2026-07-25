describe("SlidePuzzleScreen module", function()
  local SlidePuzzleScreen, Game

  setup(function()
    require("commonrequire")
    SlidePuzzleScreen = require("plugins/slidepuzzle.koplugin/slidepuzzle_screen")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
  end)

  it("should initialize SlidePuzzleScreen", function()
    local game = Game:new(3)
    local screen = SlidePuzzleScreen:new({
      game = game,
      plugin = {
        path = "plugins/slidepuzzle.koplugin",
        getStats = function() return {} end,
        settings = {
          read = function() return {} end,
        },
      },
    })
    assert.is_table(screen)
  end)
end)
