describe("SlidePuzzle main plugin module", function()
  local SlidePuzzle, Game

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SlidePuzzle = require("plugins/slidepuzzle.koplugin/main")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
  end)

  it("should initialize SlidePuzzle plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = SlidePuzzle:new({
      ui = mock_ui,
    })

    assert.is_table(plugin)
    assert.is_number(plugin.active_size)
    assert.is_table(plugin.states)
    assert.is_table(plugin.stats)
  end)

  it(
    "should manage game instances, active size, and persistence state",
    function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local plugin = SlidePuzzle:new({
        ui = mock_ui,
      })

      plugin:setActiveSize(4)
      assert.are.equal(4, plugin.active_size)

      local game = plugin:getCurrentGame()
      assert.is_table(game)
      assert.are.equal(4, game:getSize())

      plugin:saveCurrentState(game)
      assert.is_table(plugin.states["4"])

      plugin:startNewGame(3)
      assert.are.equal(3, plugin.active_size)
    end
  )

  it("should record game results and compute stats", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = SlidePuzzle:new({
      ui = mock_ui,
    })

    local game = Game:new(3)
    game.elapsed = 45
    game.moves = 12

    plugin:recordResult(game)
    local stats = plugin:getStats(3)
    assert.is_table(stats)
    assert.are.equal(45, stats.best_time)
    assert.are.equal(12, stats.best_moves)
    assert.are.equal(1, stats.plays)
  end)

  it("should build main menu item structure", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local plugin = SlidePuzzle:new({
      ui = mock_ui,
    })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)
    assert.is_table(menu_items.slidepuzzle)
    assert.is_function(menu_items.slidepuzzle.text_func)
    assert.is_function(menu_items.slidepuzzle.sub_item_table_func)

    local sub_items = menu_items.slidepuzzle.sub_item_table_func()
    assert.is_table(sub_items)
    assert.are.equal(2, #sub_items)
  end)
end)
