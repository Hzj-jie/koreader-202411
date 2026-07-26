describe("Coverbrowser ListMenu module", function()
  local ListMenu

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ListMenu = require("plugins/coverbrowser.koplugin/listmenu")
  end)

  describe("Initialization & Defaults", function()
    it("should expose ListMenu class table", function()
      assert.is_table(ListMenu)
    end)
  end)
end)
