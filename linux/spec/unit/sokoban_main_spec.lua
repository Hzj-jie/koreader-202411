describe("Sokoban main plugin module", function()
  local Sokoban

  setup(function()
    require("commonrequire")
    Sokoban = require("plugins/sokoban.koplugin/main")
  end)

  it("should initialize Sokoban plugin instance", function()
    local plugin = Sokoban:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/sokoban.koplugin",
    })

    assert.is_table(plugin)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items", function()
      local plugin = Sokoban:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/sokoban.koplugin",
      })
      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.sokoban)
    end)

    it("should register dispatcher actions", function()
      local plugin = Sokoban:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/sokoban.koplugin",
      })
      if type(plugin.onDispatcherRegisterActions) == "function" then
        plugin:onDispatcherRegisterActions()
      end
    end)
  end)
end)
