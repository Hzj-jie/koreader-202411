describe("Checkers main plugin module", function()
  local Checkers

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Checkers = require("plugins/checkers.koplugin/main")
  end)

  it("should expose Checkers main plugin class table", function()
    assert.is_table(Checkers)
  end)

  it("should load and save checkers settings safely", function()
    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    if type(instance.loadSettings) == "function" then
      instance:loadSettings()
    end
    if type(instance.saveSettings) == "function" then
      instance:saveSettings()
    end
  end)
end)
