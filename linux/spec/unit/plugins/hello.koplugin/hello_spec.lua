describe("Hello World plugin module", function()
  local Hello

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Hello = dofile("plugins/hello.koplugin/main.lua")
  end)

  describe("Initialization & Defaults", function()
    it("should expose Hello plugin module or disabled state", function()
      assert.is_table(Hello)
    end)
  end)
end)
