describe("AutoSuspend", function()
  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    local PluginShare = require("pluginshare")
    for k in pairs(PluginShare.backgroundJobs) do
      PluginShare.backgroundJobs[k] = nil
    end
  end)

  describe("suspend", function()
    local runner
    before_each(function()
      local Device = require("device")
      stub(Device, "isKobo")
      Device.isKobo.returns(true)
      local PowerD = Device:getPowerDevice()
      stub(PowerD, "isCharging")
      PowerD.isCharging.returns(false)
      stub(PowerD, "isCharged")
      PowerD.isCharged.returns(false)
      Device.input.waitEvent = function() end
      local UIManager = require("ui/uimanager")
      stub(UIManager, "suspend")
      UIManager:setRunForeverMode()
      G_reader_settings:save("auto_suspend_timeout_seconds", 10)
      require("mock_time"):install()
      -- Reset UIManager:getTime()
      UIManager:handleInput()
      UIManager:updateLastUserActionTime()
      UIManager:quit()

      runner = requireBackgroundRunner()
      UIManager:show(runner)
    end)

    after_each(function()
      local UIManager = require("ui/uimanager")
      UIManager:close(runner)
      stopBackgroundRunner()

      local Device = require("device")
      Device.isKobo:revert()
      local PowerD = Device:getPowerDevice()
      PowerD.isCharging:revert()
      PowerD.isCharged:revert()
      require("ui/uimanager").suspend:revert()
      G_reader_settings:delete("auto_suspend_timeout_seconds")
      require("mock_time"):uninstall()
    end)

    it("should be able to execute suspend when timing out", function()
      local mock_time = require("mock_time")
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local UIManager = require("ui/uimanager")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(4)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(0)
      mock_time:increase(6)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(1)
    end)

    it("should be able to deprecate last task", function()
      local mock_time = require("mock_time")
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new()
      local UIManager = require("ui/uimanager")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(4)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(0)
      UIManager:updateLastUserActionTime()
      widget:onSuspend()
      widget:onResume()
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(5)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(0)
      mock_time:increase(5)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(1)
    end)

    it("should only check shutdown after UnexpectedWakeupLimit", function()
      local mock_time = require("mock_time")
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new()
      local UIManager = require("ui/uimanager")
      mock_time:increase(1)
      UIManager:handleInput()

      -- Call handler directly since widget is not registered in UIManager
      widget:onUnexpectedWakeupLimit()

      mock_time:increase(10)
      UIManager:handleInput()
      assert.stub(UIManager.suspend).was.called(0)
    end)

    it(
      "should re-enable suspend on unplug after UnexpectedWakeupLimit",
      function()
        local mock_time = require("mock_time")
        local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
        local widget = widget_class:new()
        local UIManager = require("ui/uimanager")
        mock_time:increase(1)
        UIManager:handleInput()

        widget:onUnexpectedWakeupLimit()
        widget:onNotCharging()

        mock_time:increase(10)
        UIManager:handleInput()
        assert.stub(UIManager.suspend).was.called(1)
      end
    )
  end)

  describe("shutdown", function()
    local runner
    before_each(function()
      local Device = require("device")
      stub(Device, "isKobo")
      Device.isKobo.returns(true)
      stub(Device, "canPowerOff")
      Device.canPowerOff.returns(true)
      local PowerD = Device:getPowerDevice()
      stub(PowerD, "isCharging")
      PowerD.isCharging.returns(false)
      stub(PowerD, "isCharged")
      PowerD.isCharged.returns(false)
      Device.input.waitEvent = function() end
      local UIManager = require("ui/uimanager")
      stub(UIManager, "poweroff_action")
      UIManager:setRunForeverMode()
      G_reader_settings:save("autoshutdown_timeout_seconds", 10)
      require("mock_time"):install()
      UIManager:handleInput()
      UIManager:updateLastUserActionTime()
      UIManager:quit()

      runner = requireBackgroundRunner()
      UIManager:show(runner)
    end)

    after_each(function()
      local UIManager = require("ui/uimanager")
      UIManager:close(runner)
      stopBackgroundRunner()

      local Device = require("device")
      Device.isKobo:revert()
      Device.canPowerOff:revert()
      local PowerD = Device:getPowerDevice()
      PowerD.isCharging:revert()
      PowerD.isCharged:revert()
      require("ui/uimanager").poweroff_action:revert()
      G_reader_settings:delete("autoshutdown_timeout_seconds")
      require("mock_time"):uninstall()
    end)

    it("should be able to execute shutdown when timing out", function()
      local mock_time = require("mock_time")
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local UIManager = require("ui/uimanager")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(4)
      UIManager:handleInput()
      assert.stub(UIManager.poweroff_action).was.called(0)
      mock_time:increase(6)
      UIManager:handleInput()
      assert.stub(UIManager.poweroff_action).was.called(1)
    end)

    it("should be able to deprecate last task", function()
      local mock_time = require("mock_time")
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new()
      local UIManager = require("ui/uimanager")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(4)
      UIManager:handleInput()
      assert.stub(UIManager.poweroff_action).was.called(0)
      UIManager:updateLastUserActionTime()
      widget:onSuspend()
      widget:onResume()
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(5)
      UIManager:handleInput()
      assert.stub(UIManager.poweroff_action).was.called(0)
      mock_time:increase(5)
      UIManager:handleInput()
      assert.stub(UIManager.poweroff_action).was.called(1)
    end)
  end)

  describe("standby", function()
    local runner
    local old_auto_standby
    local Device = require("device")
    local PowerD = Device:getPowerDevice()
    local NetworkMgr = require("ui/network/manager")
    local UIManager = require("ui/uimanager")

    before_each(function()
      stub(Device, "isKobo")
      Device.isKobo.returns(true)
      stub(Device, "canStandby")
      Device.canStandby.returns(true)
      stub(Device, "standby")

      stub(PowerD, "isCharging")
      PowerD.isCharging.returns(false)
      stub(Device, "canPowerSaveWhileCharging")
      Device.canPowerSaveWhileCharging.returns(true)

      stub(NetworkMgr, "isWifiOn")
      NetworkMgr.isWifiOn.returns(false)

      local original_prevent = UIManager.preventStandby
      stub(UIManager, "preventStandby", function(self_ui)
        original_prevent(self_ui)
      end)
      local original_allow = UIManager.allowStandby
      stub(UIManager, "allowStandby", function(self_ui)
        original_allow(self_ui)
      end)
      stub(UIManager, "getNextTaskTime")
      UIManager.getNextTaskTime.returns(nil)

      old_auto_standby = G_named_settings.auto_standby_timeout_seconds
      G_named_settings.auto_standby_timeout_seconds = function()
        return 4
      end

      Device.input.waitEvent = function() end
      UIManager:setRunForeverMode()
      require("mock_time"):install()
      UIManager:handleInput()
      UIManager:updateLastUserActionTime()
      UIManager:quit()

      runner = requireBackgroundRunner()
      UIManager:show(runner)
    end)

    after_each(function()
      local UIManager = require("ui/uimanager")
      UIManager:close(runner)
      stopBackgroundRunner()

      Device.isKobo:revert()
      Device.canStandby:revert()
      Device.standby:revert()
      PowerD.isCharging:revert()
      Device.canPowerSaveWhileCharging:revert()
      NetworkMgr.isWifiOn:revert()
      UIManager.preventStandby:revert()
      UIManager.allowStandby:revert()
      UIManager.getNextTaskTime:revert()
      G_named_settings.auto_standby_timeout_seconds = old_auto_standby
      require("mock_time"):uninstall()
    end)

    it("should prevent standby initially", function()
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local mock_time = require("mock_time")
      mock_time:increase(1)
      UIManager:handleInput()
      assert.stub(UIManager.preventStandby).was.called(1)
      assert.stub(UIManager.allowStandby).was.called(0)
    end)

    it("should allow standby when timing out", function()
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local mock_time = require("mock_time")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(10)
      UIManager:handleInput()
      assert.stub(UIManager.allowStandby).was.called(1)
    end)

    it("should call Device:standby on AllowStandby event", function()
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new()

      -- Call handler directly since widget is not registered in UIManager
      widget:onAllowStandby()

      assert.stub(UIManager.getNextTaskTime).was.called(1)
      assert.stub(Device.standby).was.called_with(Device, math.huge)
    end)

    it("should call Device:standby with calculated wake_in time", function()
      UIManager.getNextTaskTime.returns(require("ui/time").s(2))
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new()

      -- Call handler directly since widget is not registered in UIManager
      widget:onAllowStandby()

      assert.stub(UIManager.getNextTaskTime).was.called(1)
      assert.stub(Device.standby).was.called_with(Device, 3)
    end)

    it("should delay standby if WiFi is on", function()
      NetworkMgr.isWifiOn.returns(true)
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local mock_time = require("mock_time")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(10)
      UIManager:handleInput()
      assert.stub(UIManager.allowStandby).was.called(0)
      assert.stub(Device.standby).was.called(0)
    end)

    it("should delay standby if charging", function()
      PowerD.isCharging.returns(true)
      Device.canPowerSaveWhileCharging.returns(false)
      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      local widget = widget_class:new() --luacheck: ignore
      local mock_time = require("mock_time")
      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(10)
      UIManager:handleInput()
      assert.stub(UIManager.allowStandby).was.called(0)
      assert.stub(Device.standby).was.called(0)
    end)
  end)

  describe("kindle", function()
    it("should reset Kindle T1 timeout", function()
      local Device = require("device")
      local PowerD = Device:getPowerDevice()
      stub(Device, "isKindle")
      Device.isKindle.returns(false) -- initially false to bypass top check

      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")

      stub(PowerD, "resetT1Timeout")
      Device.input.waitEvent = function() end
      local UIManager = require("ui/uimanager")
      UIManager:setRunForeverMode()
      require("mock_time"):install()
      UIManager:handleInput()
      UIManager:updateLastUserActionTime()
      UIManager:quit()

      Device.isKindle.returns(true)

      local runner = requireBackgroundRunner()
      UIManager:show(runner)

      local widget = widget_class:new() --luacheck: ignore
      local mock_time = require("mock_time")

      mock_time:increase(1)
      UIManager:handleInput()
      mock_time:increase(300)
      UIManager:handleInput()

      assert.stub(PowerD.resetT1Timeout).was.called(1)

      UIManager:close(runner)
      stopBackgroundRunner()
      Device.isKindle:revert()
      PowerD.resetT1Timeout:revert()
      require("mock_time"):uninstall()
    end)
  end)
end)
