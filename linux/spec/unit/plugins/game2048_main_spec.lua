describe("Game2048 main plugin module", function()
  local Game2048

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Game2048 = require("plugins/game2048.koplugin/main")
  end)

  it("should expose Game2048 plugin class table", function()
    assert.is_table(Game2048)
  end)

  it("should initialize Game2048 plugin instance", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = Game2048:new({ ui = { menu = mock_menu } })
    assert.is_table(instance)
    if type(instance.onDispatcherRegisterActions) == "function" then
      instance:onDispatcherRegisterActions()
    end
  end)
end)
