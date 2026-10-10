local spy = require("luassert.spy")

describe("Solitaire main plugin module", function()
  local Solitaire

  setup(function()
    require("commonrequire")
    Solitaire = require("plugins/solitaire.koplugin/main")
  end)

  it("should initialize Solitaire plugin instance", function()
    local registered = false
    local plugin = Solitaire:new({
      ui = {
        menu = {
          registerToMainMenu = function(self, widget)
            registered = true
          end,
        },
      },
      path = "plugins/solitaire.koplugin",
    })

    assert.is_table(plugin)
    assert.are.equal("solitaire", plugin.name)
    assert.is_false(plugin.is_doc_only)

    plugin:init()
    assert.is_true(registered)
  end)

  describe("Menu & Dispatcher Integration", function()
    it("should populate main menu items with games sorting hint", function()
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
      assert.are.equal("Solitaire", menu_items.solitaire.text)
      assert.are.equal("games", menu_items.solitaire.sorting_hint)
      assert.is_function(menu_items.solitaire.callback)
    end)

    it("should call startGame when menu callback is invoked", function()
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

      local start_called = false
      local orig_startGame = plugin.startGame
      plugin.startGame = function(self)
        start_called = true
      end
      finally(function()
        plugin.startGame = orig_startGame
      end)

      menu_items.solitaire.callback()
      assert.is_true(start_called)
    end)
  end)

  describe("startGame", function()
    it("should instantiate SolitaireUI and show it via UIManager", function()
      local shown_widget
      local UIManager = require("ui/uimanager")
      local orig_show = UIManager.show
      UIManager.show = function(self, widget)
        shown_widget = widget
      end
      finally(function()
        UIManager.show = orig_show
      end)

      local plugin = Solitaire:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
        path = "plugins/solitaire.koplugin",
      })

      plugin:startGame()

      assert.is_not_nil(shown_widget)
      assert.are.equal("solitaire_game", shown_widget.name)
      if shown_widget.onClose then
        shown_widget:onClose()
      end
    end)
  end)
end)
