describe("Coverbrowser BookInfoManager module", function()
  local BookInfoManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
  end)

  describe("Initialization & Properties", function()
    it("should expose BookInfoManager class table", function()
      assert.is_table(BookInfoManager)
    end)
  end)
end)
