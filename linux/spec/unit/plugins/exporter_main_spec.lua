describe("Exporter main plugin module", function()
  local Exporter

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Exporter = require("plugins/exporter.koplugin/main")
  end)

  it(
    "should initialize Exporter plugin instance and register actions",
    function()
      local mock_menu = { registerToMainMenu = function() end }
      local instance = Exporter:new({ ui = { menu = mock_menu } })
      assert.is_table(instance)
      assert.are.equal("exporter", instance.name)

      if type(instance.onDispatcherRegisterActions) == "function" then
        instance:onDispatcherRegisterActions()
      end
    end
  )
end)
