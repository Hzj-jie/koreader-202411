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

    if
      exit_settings.restart_koreader and exit_settings.restart_koreader.callback
    then
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
    local can_restart_stub = stub(Device, "canRestart", function()
      return false
    end)
    local LuaDefaults = require("luadefaults")
    local do_not_exit_stub = stub(LuaDefaults, "isTrue", function(self, key)
      if key == "DO_NOT_EXIT" then
        return false
      end
      return false
    end)
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_no_restart = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_no_restart.exit_menu)
    can_restart_stub:revert()
    do_not_exit_stub:revert()

    -- Clean up
    UIManager.broadcastEvent = orig_broadcast
    UIManager.suspend = orig_suspend
    UIManager.askForReboot = orig_askForReboot
    UIManager.askForPowerOff = orig_askForPowerOff
  end)

  it("provides switch_lua menu item with correct runtime toggle text and restart event", function()
    local Device = require("device")
    local UIManager = require("ui/uimanager")
    local Version = require("version")
    local LuaDefaults = require("luadefaults")

    local orig_arg = _G.arg

    finally(function()
      _G.arg = orig_arg
      package.loaded["ui/elements/common_exit_menu_table"] = nil
    end)

    local broadcast_events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      table.insert(broadcast_events, ev)
    end

    -- 1. Test when running on standard Lua: switch text is "Switch to LuaJIT"
    _G.arg = { [-1] = "./lua", [0] = "reader.lua" }
    assert.is_false(Version:isLuaJIT())
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_settings = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_settings.switch_lua)
    assert.are.equal("Switch to LuaJIT", exit_settings.switch_lua.text)

    -- 2. Test when running on LuaJIT with absolute path: switch text is "Switch to Lua"
    _G.arg = { [-1] = "/mnt/us/koreader/luajit", [0] = "reader.lua" }
    assert.is_true(Version:isLuaJIT())
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    exit_settings = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_settings.switch_lua)
    assert.are.equal("Switch to Lua", exit_settings.switch_lua.text)

    -- 3. Test when running on LuaJIT with flags (e.g. -O3): switch text is "Switch to Lua"
    _G.arg = { [-2] = "./luajit", [-1] = "-O3", [0] = "./reader.lua" }
    assert.is_true(Version:isLuaJIT())
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    exit_settings = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_settings.switch_lua)
    assert.are.equal("Switch to Lua", exit_settings.switch_lua.text)

    -- 4. Verify callback broadcasts Event:new("Restart", 89)
    broadcast_events = {}
    exit_settings.switch_lua.callback()
    assert.are.equal(1, #broadcast_events)
    assert.are.equal("onRestart", broadcast_events[1].handler)
    assert.are.equal(89, broadcast_events[1].args[1])

    -- 5. Verify switch_lua is nil when Device:canRestart() is false
    local can_restart_stub = stub(Device, "canRestart", function()
      return false
    end)
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_no_restart = require("ui/elements/common_exit_menu_table")
    assert.is_nil(exit_no_restart.switch_lua)
    can_restart_stub:revert()

    -- 6. Verify switch_lua remains non-nil when DO_NOT_EXIT is true and canRestart() is true
    local do_not_exit_stub = stub(LuaDefaults, "isTrue", function(self, key)
      if key == "DO_NOT_EXIT" then
        return true
      end
      return false
    end)
    package.loaded["ui/elements/common_exit_menu_table"] = nil
    local exit_do_not_exit = require("ui/elements/common_exit_menu_table")
    assert.is_not_nil(exit_do_not_exit.switch_lua)
    do_not_exit_stub:revert()

    -- Clean up
    UIManager.broadcastEvent = orig_broadcast
  end)
end)
