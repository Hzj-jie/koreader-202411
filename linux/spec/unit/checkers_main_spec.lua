describe("Checkers main plugin module", function()
  local Checkers

  setup(function()
    require("commonrequire")
    Checkers = require("plugins/checkers.koplugin/main")
  end)

  it("should initialize Checkers plugin instance", function()
    local plugin = Checkers:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/checkers.koplugin",
    })

    assert.is_table(plugin)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items", function()
      local plugin = Checkers:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/checkers.koplugin",
      })
      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.checkers)
    end)

    it("should register dispatcher actions", function()
      local plugin = Checkers:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/checkers.koplugin",
      })
      if type(plugin.onDispatcherRegisterActions) == "function" then
        plugin:onDispatcherRegisterActions()
      end
    end)
  end)
end)
