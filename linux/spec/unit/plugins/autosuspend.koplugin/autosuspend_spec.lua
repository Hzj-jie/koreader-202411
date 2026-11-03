describe("AutoSuspend", function()
  local stub_ui = {
    menu = {
      registerToMainMenu = function() end,
    },
  }

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
      local widget = widget_class:new({ ui = stub_ui }) --luacheck: ignore
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
      local widget = widget_class:new({ ui = stub_ui })
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
  end)

  describe("kindle", function()
    it("should be disabled on Kindle devices", function()
      local Device = require("device")
      stub(Device, "isKindle")
      Device.isKindle.returns(true)

      local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
      assert.is_true(widget_class.disabled)

      if type(widget_class.onDispatcherRegisterActions) == "function" then
        widget_class:onDispatcherRegisterActions()
      end

      Device.isKindle:revert()
    end)
  end)

  describe("Defect verifications", function()
    it(
      "unschedules active timer when disabling autosuspend timeout in pickTimeoutValue",
      function()
        local UIManager = require("ui/uimanager")
        local widget_class = dofile("plugins/autosuspend.koplugin/main.lua")
        local widget = widget_class:new({ ui = stub_ui })
        widget.auto_suspend_timeout_seconds = 180

        local scheduled = false
        local orig_scheduleIn = UIManager.scheduleIn
        local orig_unschedule = UIManager.unschedule
        UIManager.scheduleIn = function(self_uim, sec, task)
          if task == widget.task then
            scheduled = true
          end
          return orig_scheduleIn(self_uim, sec, task)
        end
        UIManager.unschedule = function(self_uim, task)
          if task == widget.task then
            scheduled = false
          end
          return orig_unschedule(self_uim, task)
        end

        local spinner
        local orig_show = UIManager.show
        UIManager.show = function(self_uim, w)
          spinner = w
        end

        finally(function()
          UIManager.scheduleIn = orig_scheduleIn
          UIManager.unschedule = orig_unschedule
          UIManager.show = orig_show
        end)

        widget:_start()
        assert.is_true(scheduled)

        widget:pickTimeoutValue(
          nil,
          "Timeout for autosuspend",
          "Enter time",
          "auto_suspend_timeout_seconds",
          180,
          { 60, 24 * 3600 }
        )
        assert.is_table(spinner)
        spinner.extra_callback({ onExit = function() end })

        assert.is_false(widget:_enabled())
        assert.is_false(scheduled)
      end
    )
  end)
end)
