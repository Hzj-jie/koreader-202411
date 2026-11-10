describe("SlidePuzzle winning move", function()
  local Game, I18n, InfoMessage, LuaSettings, Screen, SlidePuzzle, T, UIManager
  local tmp_settings_path, shown_screens

  setup(function()
    require("commonrequire")

    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
    I18n = require("plugins/slidepuzzle.koplugin/slidepuzzle_i18n")
    InfoMessage = require("ui/widget/infomessage")
    LuaSettings = require("luasettings")
    Screen = require("plugins/slidepuzzle.koplugin/slidepuzzle_screen")
    SlidePuzzle = require("plugins/slidepuzzle.koplugin/main")
    T = require("ffi/util").template
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    tmp_settings_path = os.tmpname()
    os.remove(tmp_settings_path)
    shown_screens = {}
    I18n.setActive("default")
  end)

  after_each(function()
    for _, screen in ipairs(shown_screens) do
      screen:stopTicker()
      UIManager:closeIfShown(screen)
    end
    for i = #UIManager._window_stack, 1, -1 do
      UIManager:closeIfShown(UIManager._window_stack[i].widget)
    end
    for i = #UIManager._task_queue, 1, -1 do
      UIManager:unschedule(UIManager._task_queue[i].action)
    end
    UIManager:clearRenderStack()
    I18n.setActive("default")
    if tmp_settings_path then
      os.remove(tmp_settings_path)
      os.remove(tmp_settings_path .. ".old")
      tmp_settings_path = nil
    end
  end)

  local function create_near_win_screen()
    local plugin = SlidePuzzle:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    plugin.settings_file = tmp_settings_path
    plugin.settings = LuaSettings:open(tmp_settings_path)
    plugin.active_size = 3
    plugin.states = plugin.settings:readTableRef("states")
    plugin.stats = plugin.settings:readTableRef("stats")

    -- Create a 3x3 board one move away from solved: slide tile 8 at (3, 2)
    -- into the empty cell at (3, 3), leaving the gap at (3, 2).
    local game = Game:new(3)
    game.won = false
    game.started = false
    game.moves = 0
    game.elapsed = 12
    assert.is_true(game:moveTileAt(3, 2))
    assert.is_false(game:isWon())

    plugin._cached_game = game
    local screen = Screen:new({
      plugin = plugin,
      game = game,
    })
    plugin.screen = screen
    table.insert(shown_screens, screen)
    UIManager:show(screen)
    assert.is_true(screen.tick_scheduled)
    return plugin, game, screen
  end

  local function assert_win_completed(
    plugin,
    game,
    screen,
    record_spy,
    save_spy
  )
    assert.is_true(game:isWon())
    assert.are.equal(2, game:getMoves())
    assert.is_false(screen.tick_scheduled)
    for _, task in ipairs(UIManager._task_queue) do
      assert.are_not.equal(screen.tick_handler, task.action)
    end

    assert.spy(record_spy).was_called(1)
    assert.spy(save_spy).was_called(1)

    -- Real UIManager:forceRepaint() must have drained screen before showing the
    -- solved InfoMessage overlay.
    assert.is_nil(UIManager._dirty[screen])

    local shown = UIManager:getTopmostVisibleWidget()
    assert.are_not.equal(screen, shown)
    assert.are.equal(InfoMessage, getmetatable(shown))
    assert.are.equal(
      T(
        I18n.t("You solved the %1x%1 puzzle!\nMoves: %2\nTime: %3"),
        3,
        2,
        "00:12"
      ),
      shown.text
    )
    assert.are.equal(
      T(I18n.t("Solved in %1 moves and %2."), 2, "00:12"),
      screen.message_text.text
    )
    assert.are.equal(
      T(I18n.t("%1x%1 Puzzle    Moves: %2    Time: %3"), 3, 2, "00:12"),
      screen.header_text.text
    )

    local persisted = LuaSettings:open(tmp_settings_path)
    local stats = persisted:read("stats")["3"]
    local state = persisted:read("states")["3"]
    assert.are.equal(1, stats.plays)
    assert.are.equal(2, stats.best_moves)
    assert.are.equal(12, stats.best_time)
    assert.is_true(state.won)
    assert.are.equal(2, state.moves)
  end

  it(
    "completes a winning tap without crashing and shows the solved message",
    function()
      local plugin, game, screen = create_near_win_screen()
      local record_spy = spy.on(plugin, "recordResult")
      local save_spy = spy.on(plugin, "saveCurrentState")

      screen:performTap(3, 3)

      assert_win_completed(plugin, game, screen, record_spy, save_spy)
    end
  )

  it(
    "completes a winning swipe without crashing and shows the solved message",
    function()
      local plugin, game, screen = create_near_win_screen()
      local record_spy = spy.on(plugin, "recordResult")
      local save_spy = spy.on(plugin, "saveCurrentState")

      screen:performSwipe("left")

      assert_win_completed(plugin, game, screen, record_spy, save_spy)
    end
  )
end)
