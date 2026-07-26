describe("ExternalKeyboard plugin main module", function()
  local ExternalKeyboard, DataStorage, UIManager

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

    ExternalKeyboard = require("plugins/externalkeyboard.koplugin/main")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize ExternalKeyboard plugin module", function()
      assert.is_table(ExternalKeyboard)
      assert.is_boolean(ExternalKeyboard.disabled)
    end)
  end)
end)
