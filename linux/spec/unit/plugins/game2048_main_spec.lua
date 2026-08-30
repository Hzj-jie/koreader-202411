describe("Game2048 main plugin module", function()
  local Game2048
  local UIManager
  local Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Game2048 = require("plugins/game2048.koplugin/main")
    UIManager = require("ui/uimanager")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should initialize Game2048 plugin instance, menu, and state storage", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = Game2048:new({ ui = { menu = mock_menu } })
    assert.is_table(instance)
    assert.is_table(instance.state)
    assert.is_table(instance.storage)

    local menu_items = {}
    instance:addToMainMenu(menu_items)
    assert.is_table(menu_items.game2048)

    -- Storage save and read
    instance.storage:saveState(instance.state)
    instance.storage:readState(instance.state)
    instance.storage:flush()
  end)

  it("should manage Game2048Info timer and score state", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = Game2048:new({ ui = { menu = mock_menu } })
    local info = instance.state.info

    info:reset()
    assert.is_false(info:isRunning())
    info:start()
    assert.is_true(info:isRunning())
    info:move(10)
    assert.are.equal(info.score, 10)
    assert.are.equal(info.best, 10)
    assert.are.equal(info.moves, 1)
    info:stop()
    assert.is_false(info:isRunning())

    local saved = info:save()
    assert.is_table(saved)
    info:read(saved)

    local untracked = info:saveUntracked()
    assert.is_table(untracked)
    info:readUntracked(untracked)

    info:newGameReset()
    assert.are.equal(info.score, 0)
    assert.are.equal(info.moves, 0)
  end)

  it("should manage Game2048State moves, history undo/redo, and profile switching", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = Game2048:new({ ui = { menu = mock_menu } })
    local state = instance.state

    state:reset()
    state:newGame()

    -- Try moves in all 4 directions
    state:move("up")
    state:move("down")
    state:move("left")
    state:move("right")

    state:pushToHistory()
    state:historyUndo()
    state:historyRedo()

    -- Profile switch
    state.settings.profile = "profile_2"
    instance.storage:switchGameState(state)
    assert.are.equal(state.profile, "profile_2")
  end)

  it("should manage Game2048Screen UI lifecycle, inputs, themes, and dialogs", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function() end
    UIManager.close = function() end

    local mock_menu = { registerToMainMenu = function() end }
    local instance = Game2048:new({ ui = { menu = mock_menu } })

    instance:showGame()
    assert.is_table(instance.screen)
    local screen = instance.screen

    -- Screen moves, newGame, undo, redo
    screen:onGame2048Move("left")
    screen:onGame2048Move("right")
    screen:onUndo()
    screen:onRedo()
    screen:newGame()

    -- Theme and Profile changes
    screen:onThemeChange("light")
    screen:onProfileChange("default")

    -- Settings, Suspend, Resume
    screen._config.showConfigMenu = function() end
    screen:onShowSettings()
    screen:onNewSettings()
    screen:onSuspend()
    screen:onResume()
    screen:onSettingsMenu()
    screen:_showGameOver()

    -- Paint to Blitbuffer
    local bb = Blitbuffer.new(screen.dimen.w or 600, screen.dimen.h or 800)
    screen:paintTo(bb, 0, 0)
    bb:free()

    -- Close
    instance:closeScreen()
    assert.is_nil(instance.screen)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)
end)
