describe("ReadTimer plugin main module", function()
  local ReadTimer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReadTimer = require("plugins/readtimer.koplugin/main")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize ReadTimer plugin instance", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })
      assert.is_table(rt)
    end)

    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local rt = ReadTimer:new({
        ui = mock_ui,
      })
      local menu_items = {}
      rt:addToMainMenu(menu_items)
      assert.is_table(menu_items.read_timer)
    end)
  end)
end)
