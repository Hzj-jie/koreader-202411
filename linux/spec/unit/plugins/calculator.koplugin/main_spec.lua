describe("Calculator plugin main module", function()
  local Calculator, DataStorage, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    UIManager = require("ui/uimanager")

    _G.G_reader_settings = {
      read = function(self, key)
        return nil
      end,
      readTableRef = function(self, key, default)
        return default or {}
      end,
      readSetting = function(self, key, default)
        return default
      end,
      has = function(self, key)
        return false
      end,
      nilOrTrue = function(self, key)
        return true
      end,
      isTrue = function(self, key)
        return false
      end,
      save = function() end,
      saveSetting = function() end,
      flush = function() end,
    }

    Calculator = require("plugins/calculator.koplugin/main")
  end)

  describe("Initialization & Properties", function()
    it("should set default calculator properties and modes", function()
      assert.is_table(Calculator)
      assert.are.equal(Calculator.name, "calculator")
      assert.is_table(Calculator.angle_modes)
      assert.is_table(Calculator.number_formats)
    end)

    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local calc = Calculator:new({
        ui = mock_ui,
      })

      local menu_items = {}
      calc:addToMainMenu(menu_items)
      assert.is_table(menu_items.calculator)
    end)

    it("should register dispatcher actions", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local calc = Calculator:new({
        ui = mock_ui,
      })
      if type(calc.onDispatcherRegisterActions) == "function" then
        calc:onDispatcherRegisterActions()
      end
    end)
  end)
end)
