describe("Coverbrowser CoverMenu module", function()
  local CoverMenu

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CoverMenu = require("plugins/coverbrowser.koplugin/covermenu")
  end)

  describe("Initialization & Defaults", function()
    it("should expose CoverMenu helper methods table", function()
      assert.is_table(CoverMenu)
      assert.is_function(CoverMenu.updateCache)
    end)

    it("should handle updateCache safely", function()
      if type(CoverMenu.updateCache) == "function" then
        CoverMenu:updateCache()
      end
    end)
  end)
end)
