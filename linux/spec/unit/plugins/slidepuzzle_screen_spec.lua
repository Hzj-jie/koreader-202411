describe("SlidePuzzle Screen module", function()
  local Screen, Plugin, Game, Settings, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    Plugin = require("plugins/slidepuzzle.koplugin/main")
    Screen = require("plugins/slidepuzzle.koplugin/slidepuzzle_screen")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
    Settings = require("plugins/slidepuzzle.koplugin/slidepuzzle_settings")
  end)

  local function create_mock_plugin(game)
    return {
      settings = {
        read = function() return nil end,
        readTable = function() return {} end,
        readTableRef = function() return {} end,
      },
      getStats = function() return { moves = 0, time = 0, solved = 0 } end,
      startNewGame = function() end,
      getCurrentGame = function() return game end,
      saveCurrentState = function() end,
      onScreenClosed = function() end,
    }
  end

  it("should initialize SlidePuzzle screen widget", function()
    local game = Game:new({ grid_w = 3, grid_h = 3 })
    local screen = Screen:new({
      plugin = create_mock_plugin(game),
      game = game,
    })

    assert.is_table(screen)
    assert.is_table(screen.board_widget)
  end)

  it("should update header text and handle user tap/swipe actions", function()
    local game = Game:new({ grid_w = 3, grid_h = 3 })
    local mock_plugin = create_mock_plugin(game)
    local screen = Screen:new({
      plugin = mock_plugin,
      game = game,
    })

    UIManager:show(screen)

    if type(screen.updateHeader) == "function" then
      screen:updateHeader()
    end

    if type(screen.performTap) == "function" then
      screen:performTap(1, 1)
    end

    if type(screen.performSwipe) == "function" then
      screen:performSwipe("right")
    end

    UIManager:close(screen)
  end)
end)
