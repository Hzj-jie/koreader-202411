describe("Sokoban main plugin module", function()
  local Sokoban

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Sokoban = require("plugins/sokoban.koplugin/main")
  end)

  it("should initialize Sokoban plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = Sokoban:new({
      ui = mock_ui,
      path = "plugins/sokoban.koplugin",
    })
    assert.is_table(plugin)
  end)

  it("should load settings and start level", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = Sokoban:new({
      ui = mock_ui,
      path = "plugins/sokoban.koplugin",
    })

    plugin:_loadSettings()
    assert.is_string(plugin.current_set)
    assert.is_number(plugin.current_level)

    plugin:startLevel(1, 1)
    assert.are.equal(1, plugin.current_level)
    assert.is_table(plugin.game)
  end)

  it("should add item to main menu and trigger callback", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = Sokoban:new({
      ui = mock_ui,
      path = "plugins/sokoban.koplugin",
    })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)
    assert.is_table(menu_items.sokoban)
    assert.is_function(menu_items.sokoban.callback)
  end)
end)
