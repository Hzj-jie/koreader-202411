describe("SlidePuzzle Screen module", function()
  local Screen, Plugin, Game, Settings, UIManager, Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    Plugin = require("plugins/slidepuzzle.koplugin/main")
    Screen = require("plugins/slidepuzzle.koplugin/slidepuzzle_screen")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
    Settings = require("plugins/slidepuzzle.koplugin/slidepuzzle_settings")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  local function create_mock_plugin(game)
    local cur_game = game
    return {
      settings = {
        read = function()
          return nil
        end,
        readTable = function()
          return {}
        end,
        readTableRef = function()
          return {}
        end,
      },
      getStats = function(self, size)
        return { best_moves = 10, best_time = 30, plays = 2 }
      end,
      startNewGame = function(self, size)
        cur_game = Game:new(size or 3)
      end,
      getCurrentGame = function()
        return cur_game
      end,
      setActiveSize = function(self, size)
        cur_game = Game:new(size)
      end,
      recordResult = function() end,
      saveCurrentState = function() end,
      onScreenClosed = function() end,
    }
  end

  it("should initialize SlidePuzzle screen widget", function()
    local game = Game:new(3)
    local screen = Screen:new({
      plugin = create_mock_plugin(game),
      game = game,
    })

    assert.is_table(screen)
    assert.is_table(screen.board_widget)
    assert.is_table(screen.header_text)
    assert.is_table(screen.best_text)
    assert.is_table(screen.message_text)

    screen:stopTicker()
  end)

  it("should update header, timer tick, best label, and messages", function()
    local game = Game:new(3)
    local mock_plugin = create_mock_plugin(game)
    local screen = Screen:new({
      plugin = mock_plugin,
      game = game,
    })

    screen:updateHeader()
    screen:updateBestLabel()
    screen:updateMessage("Custom message")
    assert.are.equal(screen.message_text.text, "Custom message")

    -- Test tick
    screen:_onTick()

    screen:stopTicker()
  end)

  it("should handle user tap/swipe, moves, new game, and size switches", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function() end
    UIManager.close = function() end

    local game = Game:new(3)
    local mock_plugin = create_mock_plugin(game)
    local screen = Screen:new({
      plugin = mock_plugin,
      game = game,
    })

    -- Tap tiles
    screen:performTap(1, 1)
    screen:performTap(3, 3)

    -- Swipes
    screen:performSwipe("up")
    screen:performSwipe("down")
    screen:performSwipe("left")
    screen:performSwipe("right")

    -- Size Dialog and Switch
    screen:showSizeDialog()
    screen:switchSize(4)
    assert.are.equal(screen.game:getSize(), 4)

    -- Stats
    screen:showStats()

    -- New game
    screen:startNewGame()

    -- Paint to Blitbuffer
    local bb = Blitbuffer.new(600, 800)
    screen:paintTo(bb, 0, 0)
    bb:free()

    -- Close
    screen:onClose()

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)
end)
