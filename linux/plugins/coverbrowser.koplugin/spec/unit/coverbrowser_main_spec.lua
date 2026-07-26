describe("CoverBrowser plugin main module", function()
  local CoverBrowser

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CoverBrowser = require("plugins/coverbrowser.koplugin/main")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize CoverBrowser plugin instance", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local cb = CoverBrowser:new({
        ui = mock_ui,
      })
      assert.is_table(cb)
    end)

    it("should expose modes list", function()
      local mock_ui = {
        file_chooser = {},
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local cb = CoverBrowser:new({
        ui = mock_ui,
      })
      assert.is_table(cb.modes)
      assert.is_true(#cb.modes >= 5)
    end)
  end)
end)
