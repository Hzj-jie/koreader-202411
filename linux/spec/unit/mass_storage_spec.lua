describe("MassStorage element", function()
  local MassStorage, Device, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MassStorage = require("ui/elements/mass_storage")
    Device = require("device")
    UIManager = require("ui/uimanager")
  end)

  it("should query confirmation and enabled settings", function()
    assert.is_boolean(MassStorage:requireConfirmation())
    assert.is_boolean(MassStorage:isEnabled())
  end)

  it(
    "should build settings and actions menu tables and invoke callbacks",
    function()
      local settings_menu = MassStorage:getSettingsMenuTable()
      assert.is_table(settings_menu)
      assert.are.equal(2, #settings_menu)
      assert.is_function(settings_menu[1].checked_func)
      assert.is_function(settings_menu[1].callback)
      settings_menu[1].callback()
      assert.is_boolean(settings_menu[1].checked_func())

      assert.is_function(settings_menu[2].checked_func)
      assert.is_function(settings_menu[2].callback)
      settings_menu[2].callback()
      assert.is_boolean(settings_menu[2].checked_func())

      local actions_menu = MassStorage:getActionsMenuTable()
      assert.is_table(actions_menu)
      assert.is_function(actions_menu.enabled_func)
      assert.is_function(actions_menu.callback)
    end
  )

  it("should handle start and dismiss lifecycle and callbacks", function()
    G_reader_settings:save("mass_storage_disabled", false)
    G_reader_settings:save("mass_storage_confirmation_disabled", false)

    local old_can = Device.canToggleMassStorage
    Device.canToggleMassStorage = function()
      return true
    end

    local orig_quit = UIManager.quit
    local orig_flush = UIManager.flushSettings
    local orig_broadcast = UIManager.broadcastEvent
    local quit_code = nil
    UIManager.quit = function(self, code)
      quit_code = code
    end
    UIManager.flushSettings = function() end
    UIManager.broadcastEvent = function() end

    -- Trigger start with confirmation
    MassStorage:start(true)
    assert.is_table(MassStorage.usbms_widget)

    -- Test cancel_callback
    if MassStorage.usbms_widget.cancel_callback then
      MassStorage.usbms_widget.cancel_callback()
    end
    assert.is_nil(MassStorage.usbms_widget)

    -- Trigger start again and test ok_callback
    MassStorage:start(true)
    assert.is_table(MassStorage.usbms_widget)
    if MassStorage.usbms_widget.ok_callback then
      MassStorage.usbms_widget.ok_callback()
    end
    assert.are_equal(86, quit_code)
    MassStorage:dismiss()

    -- Trigger start without confirmation
    quit_code = nil
    MassStorage:start(false)
    assert.are_equal(86, quit_code)

    -- When toggle is disabled, start should return early
    Device.canToggleMassStorage = function()
      return false
    end
    MassStorage:start(true)
    assert.is_nil(MassStorage.usbms_widget)

    Device.canToggleMassStorage = old_can
    UIManager.quit = orig_quit
    UIManager.flushSettings = orig_flush
    UIManager.broadcastEvent = orig_broadcast
  end)
end)
