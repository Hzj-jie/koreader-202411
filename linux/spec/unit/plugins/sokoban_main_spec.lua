describe("Sokoban main plugin module", function()
  local Sokoban, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    UIManager = require("ui/uimanager")

    Sokoban = require("plugins/sokoban.koplugin/main")
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  local function createMockSokoban()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = Sokoban:new({
      ui = mock_ui,
      path = "plugins/sokoban.koplugin",
    })
    plugin.settings = {
      data = {},
      read = function(self, key)
        return self.data[key]
      end,
      save = function(self, key, val)
        self.data[key] = val
      end,
      flush = function() end,
    }
    return plugin
  end

  it(
    "should initialize Sokoban plugin instance and register main menu",
    function()
      local plugin = createMockSokoban()
      assert.is_table(plugin)

      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.sokoban)
      assert.is_function(menu_items.sokoban.callback)
    end
  )

  it(
    "should load settings, reconcile furthest_reached, and save settings",
    function()
      local plugin = createMockSokoban()
      local set_name = "Microban"
      plugin.settings.data = {
        current_set = set_name,
        current_level = 3,
        last_played_levels = { [set_name] = 3 },
        best_moves = { [set_name] = { [1] = 10, [2] = 20, [3] = 30 } },
        best_pushes = { [set_name] = { [1] = 5, [2] = 8, [3] = 12 } },
        furthest_reached = { [set_name] = 1 }, -- Out of sync with best_moves
      }

      plugin:_loadSettings()
      assert.are.equal(set_name, plugin.current_set)
      assert.are.equal(3, plugin.current_level)
      -- furthest_reached should be reconciled to at least max_solved + 1 = 4
      assert.are.equal(4, plugin.furthest_reached[set_name])

      plugin.current_level = 4
      plugin:_saveSettings()
      assert.are.equal(4, plugin.settings:read("current_level"))
    end
  )

  it(
    "should clamp level numbers in startLevel and manage widget lifecycle",
    function()
      local plugin = createMockSokoban()
      plugin:_loadSettings()

      local old_show = UIManager.show
      local old_close = UIManager.close
      local shown_widget
      local closed_widget
      UIManager.show = function(self, w)
        shown_widget = w
      end
      UIManager.close = function(self, w)
        closed_widget = w
      end

      -- Clamp level < 1
      plugin:startLevel(1, -5)
      assert.are.equal(1, plugin.current_level)
      assert.is_not_nil(plugin.widget)
      assert.are.equal(plugin.widget, shown_widget)

      -- Starting new level closes previous widget
      local prev_widget = plugin.widget
      plugin:startLevel(1, 2)
      assert.are.equal(2, plugin.current_level)
      assert.are.equal(prev_widget, closed_widget)

      -- Clamp level > max
      plugin:startLevel(1, 9999)
      assert.is_true(plugin.current_level <= 155)

      local current_widget = plugin.widget
      plugin:_onClose()
      assert.are.equal(current_widget, closed_widget)
      assert.is_nil(plugin.widget)

      UIManager.show = old_show
      UIManager.close = old_close
    end
  )

  it("should handle _statusText, moves, restart, and skip", function()
    local plugin = createMockSokoban()
    plugin:_loadSettings()
    local old_show = UIManager.show
    local old_close = UIManager.close
    UIManager.show = function() end
    UIManager.close = function() end

    plugin:startLevel(1, 1)
    local status = plugin:_statusText()
    assert.is_string(status)
    assert.is_not_nil(status:find("Moves: 0"))
    assert.is_not_nil(status:find("Pushes: 0"))

    -- Move in valid direction
    plugin:_onMove(1, 0)
    assert.is_number(plugin.game.moves)

    -- Restart level
    plugin.game.moves = 5
    plugin:_onRestart()
    assert.are.equal(0, plugin.game.moves)

    -- Skip level
    local level_before = plugin.current_level
    plugin:_onSkip(1, level_before)
    assert.are.equal(level_before + 1, plugin.current_level)

    UIManager.show = old_show
    UIManager.close = old_close
  end)

  it("should open settings dialog", function()
    local plugin = createMockSokoban()
    plugin:_loadSettings()
    local old_show = UIManager.show
    local shown_settings
    UIManager.show = function(self, w)
      shown_settings = w
    end

    plugin:openSettings()
    assert.is_not_nil(shown_settings)
    assert.is_table(shown_settings)
    assert.are.equal(plugin.current_set, shown_settings.current_set)

    UIManager.show = old_show
  end)

  it(
    "should save best scores to settings on _onSolved [exposes production bug in Sokoban:_onSolved()]",
    function()
      local plugin = createMockSokoban()
      plugin:_loadSettings()
      local old_show = UIManager.show
      UIManager.show = function() end

      plugin:startLevel(1, 1)
      plugin.game.moves = 14
      plugin.game.pushes = 6

      -- Wipe settings data to verify _onSolved saves them
      plugin.settings.data["best_moves"] = nil
      plugin.settings.data["best_pushes"] = nil

      plugin:_onSolved()

      -- Memory state was updated
      assert.are.equal(
        14,
        plugin.best_moves[plugin.current_set][plugin.current_level]
      )
      assert.are.equal(
        6,
        plugin.best_pushes[plugin.current_set][plugin.current_level]
      )

      -- Production bug: _onSolved does not call _saveSettings(), so settings are not saved
      local saved_moves = plugin.settings:read("best_moves")
      assert.is_not_nil(saved_moves)
      assert.is_not_nil(saved_moves[plugin.current_set])
      assert.are.equal(
        14,
        saved_moves[plugin.current_set][plugin.current_level]
      )

      UIManager.show = old_show
    end
  )
end)
