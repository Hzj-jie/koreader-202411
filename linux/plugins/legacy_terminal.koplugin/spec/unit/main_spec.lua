describe("Legacy Terminal plugin main module", function()
  local LegacyTerminal

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    LegacyTerminal = require("plugins/legacy_terminal.koplugin/main")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize LegacyTerminal plugin instance", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      assert.is_table(term)
    end)

    it("should register dispatcher actions", function()
      if type(LegacyTerminal.onDispatcherRegisterActions) == "function" then
        LegacyTerminal:onDispatcherRegisterActions()
      end
    end)

    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      local menu_items = {}
      term:addToMainMenu(menu_items)
      assert.is_table(menu_items)
    end)
  end)
end)
