describe("Solitaire main plugin module", function()
  local Solitaire

  setup(function()
    require("commonrequire")
    Solitaire = require("plugins/solitaire.koplugin/main")
  end)

  it("should initialize Solitaire plugin instance", function()
    local plugin = Solitaire:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/solitaire.koplugin",
    })

    assert.is_table(plugin)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items", function()
      local plugin = Solitaire:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/solitaire.koplugin",
      })
      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.solitaire)
    end)

    it("should register dispatcher actions", function()
      local plugin = Solitaire:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/solitaire.koplugin",
      })
      if type(plugin.onDispatcherRegisterActions) == "function" then
        plugin:onDispatcherRegisterActions()
      end
    end)
  end)
end)
