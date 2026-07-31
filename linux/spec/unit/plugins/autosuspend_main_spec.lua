describe("AutoSuspend main plugin module", function()
  local AutoSuspend, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    local old_canSuspend = Device.canSuspend
    Device.canSuspend = function() return true end

    AutoSuspend = require("plugins/autosuspend.koplugin/main")
    Device.canSuspend = old_canSuspend
  end)

  it("should initialize AutoSuspend plugin and check enabled flags", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    assert.is_table(inst)
    assert.is_boolean(inst:_enabled())
    assert.is_boolean(inst:_enabledStandby())
    assert.is_boolean(inst:_enabledShutdown())
  end)

  it("should add AutoSuspend configuration items to main menu", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    local menu_items = {}
    inst:addToMainMenu(menu_items)

    assert.is_table(menu_items.autosuspend)
    assert.is_function(menu_items.autosuspend.checked_func)
    assert.is_function(menu_items.autosuspend.text_func)
    assert.is_string(menu_items.autosuspend.text_func())
    assert.is_boolean(menu_items.autosuspend.checked_func())
  end)

  it("should schedule suspend and shutdown tasks safely", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    inst:_schedule()
    inst:_unschedule()
  end)
end)
