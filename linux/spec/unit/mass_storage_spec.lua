describe("MassStorage element", function()
  local MassStorage, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MassStorage = require("ui/elements/mass_storage")
    Device = require("device")
  end)

  it("should query confirmation and enabled settings", function()
    assert.is_boolean(MassStorage:requireConfirmation())
    assert.is_boolean(MassStorage:isEnabled())
  end)

  it("should build settings and actions menu tables", function()
    local settings_menu = MassStorage:getSettingsMenuTable()
    assert.is_table(settings_menu)
    assert.are.equal(2, #settings_menu)
    assert.is_function(settings_menu[1].checked_func)
    assert.is_function(settings_menu[1].callback)

    local actions_menu = MassStorage:getActionsMenuTable()
    assert.is_table(actions_menu)
    assert.is_function(actions_menu.enabled_func)
    assert.is_function(actions_menu.callback)
  end)

  it("should handle start and dismiss lifecycle", function()
    local old_can = Device.canToggleMassStorage
    Device.canToggleMassStorage = function() return true end

    -- Trigger start with confirmation
    MassStorage:start(true)
    assert.is_table(MassStorage.usbms_widget)

    -- Dismiss confirmation dialog
    MassStorage:dismiss()
    assert.is_nil(MassStorage.usbms_widget)

    -- When toggle is disabled, start should return early without creating widget
    Device.canToggleMassStorage = function() return false end
    MassStorage:start(true)
    assert.is_nil(MassStorage.usbms_widget)

    Device.canToggleMassStorage = old_can
  end)
end)
