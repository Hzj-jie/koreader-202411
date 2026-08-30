describe("SSH plugin main module", function()
  local SSH, util, Device

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    util = require("util")
    Device = require("device")

    local old_pathExists = util.pathExists
    util.pathExists = function(path)
      if path and path:find("dropbear") then
        return true
      end
      return old_pathExists(path)
    end

    SSH = require("plugins/SSH.koplugin/main")
    util.pathExists = old_pathExists
  end)

  it("should initialize SSH plugin instance and register actions", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = SSH:new({ ui = { menu = mock_menu } })
    assert.is_table(instance)
    assert.are.equal("SSH", instance.name)

    if type(instance.onDispatcherRegisterActions) == "function" then
      instance:onDispatcherRegisterActions()
    end
  end)

  it("should check if SSH server is running", function()
    local mock_menu = { registerToMainMenu = function() end }
    local instance = SSH:new({ ui = { menu = mock_menu } })

    if type(instance.isRunning) == "function" then
      local running = instance:isRunning()
      assert.is_boolean(running)
    end
  end)
end)
