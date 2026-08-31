local stub = require("luassert.stub")

describe("common_exit_menu_table", function()
  setup(function()
    require("commonrequire")
  end)

  it("should provide exit callbacks and respect device capabilities", function()
    local Device = require("device")
    local UIManager = require("ui/uimanager")

    local broadcast_events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      table.insert(broadcast_events, ev)
    end

    local orig_suspend = UIManager.suspend
    local suspended = false
    UIManager.suspend = function()
      suspended = true
    end

    local reboot_asked = false
    local orig_askForReboot = UIManager.askForReboot
    UIManager.askForReboot = function()
      reboot_asked = true
    end

    local poweroff_asked = false
    local orig_askForPowerOff = UIManager.askForPowerOff
    UIManager.askForPowerOff = function()
      poweroff_asked = true
    end

    -- Test default loading
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_settings = require("ui/elements/common_exit_menu_table")

    if exit_settings.exit_menu and exit_settings.exit_menu.hold_callback then
      exit_settings.exit_menu.hold_callback()
      assert.is_true(#broadcast_events > 0)
    end

    if exit_settings.exit and exit_settings.exit.callback then
      exit_settings.exit.callback()
    end

    if exit_settings.restart_koreader and exit_settings.restart_koreader.callback then
      exit_settings.restart_koreader.callback()
    end

    if exit_settings.sleep and exit_settings.sleep.callback then
      exit_settings.sleep.callback()
      assert.is_true(suspended)
    end

    if exit_settings.reboot and exit_settings.reboot.callback then
      exit_settings.reboot.callback()
      assert.is_true(reboot_asked)
    end

    if exit_settings.poweroff and exit_settings.poweroff.callback then
      exit_settings.poweroff.callback()
      assert.is_true(poweroff_asked)
    end

    -- Test when canRestart is false
    local can_restart_stub = stub(Device, "canRestart", function() return false end)
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_no_restart = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_no_restart.exit_menu)
    can_restart_stub:revert()

    -- Clean up
    UIManager.broadcastEvent = orig_broadcast
    UIManager.suspend = orig_suspend
    UIManager.askForReboot = orig_askForReboot
    UIManager.askForPowerOff = orig_askForPowerOff
  end)
end)
