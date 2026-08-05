describe("OPDSBrowser module", function()
  local OPDSBrowser, DataStorage, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    UIManager = require("ui/uimanager")

    _G.G_reader_settings = {
      readTableRef = function(self, key, default)
        return default or {}
      end,
      readSetting = function(self, key, default)
        return default
      end,
      read = function(self, key, default)
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
      saveSetting = function() end,
      flush = function() end,
    }

    OPDSBrowser = require("plugins/opds.koplugin/opdsbrowser")
  end)

  describe("Initialization & Default Servers", function()
    it("should initialize default servers list", function()
      assert.is_table(OPDSBrowser.opds_servers)
      assert.truthy(#OPDSBrowser.opds_servers > 0)
      assert.are.equal(OPDSBrowser.opds_servers[1].title, "Project Gutenberg")
    end)

    it("should have correct acquisition and image rel patterns", function()
      assert.truthy(OPDSBrowser.catalog_type)
      assert.truthy(OPDSBrowser.acquisition_rel)
      assert.truthy(OPDSBrowser.thumbnail_rel)
    end)
  end)

  describe("Browser Instance & Navigation", function()
    it(
      "should create OPDSBrowser menu instance and generate root item table",
      function()
        local browser = OPDSBrowser:new({
          title = "OPDS Catalogs",
        })

        assert.is_table(browser)
        assert.are.equal(browser.title, "OPDS Catalogs")

        if type(browser.genItemTableFromRoot) == "function" then
          local item_tbl = browser:genItemTableFromRoot()
          assert.is_table(item_tbl)
          assert.truthy(#item_tbl > 0)
        end
      end
    )

    it("should handle dispatcher registration", function()
      local browser = OPDSBrowser:new({
        title = "OPDS Catalogs",
      })
      if type(browser.onDispatcherRegisterActions) == "function" then
        browser:onDispatcherRegisterActions()
      end
    end)
  end)
end)
