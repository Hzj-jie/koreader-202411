describe("Game2048 plugin main module", function()
  local Game2048

  setup(function()
    require("commonrequire")
    Game2048 = require("plugins/game2048.koplugin/main")
  end)

  it("should initialize Game2048 main plugin instance", function()
    local plugin = Game2048:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/game2048.koplugin",
    })

    assert.is_table(plugin)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items", function()
      local plugin = Game2048:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/game2048.koplugin",
      })
      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.game2048)
    end)

    it("should register dispatcher actions", function()
      local plugin = Game2048:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/game2048.koplugin",
      })
      if type(plugin.onDispatcherRegisterActions) == "function" then
        plugin:onDispatcherRegisterActions()
      end
    end)
  end)
end)
