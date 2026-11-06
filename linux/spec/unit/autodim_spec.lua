describe("AutoDim widget tests", function()
  local Device, PowerD, MockTime, class, AutoDim, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MockTime = require("mock_time")
    MockTime:install()

    PowerD = require("device/generic/powerd"):new({
      frontlight = 10,
    })
    PowerD.frontlightIntensityHW = function()
      return 10
    end
    PowerD.setIntensityHW = function(self, intensity)
      self.frontlight = intensity
    end
    PowerD.resetT1Timeout = function() end
  end)

  teardown(function()
    MockTime:uninstall()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  local mock_ui

  before_each(function()
    Device = require("device")
    stub(Device, "isKindle")
    Device.isKindle.returns(false)
    stub(Device, "hasEinkScreen")
    Device.hasEinkScreen.returns(false)

    Device.powerd = PowerD:new({
      device = Device,
    })
    Device.input.waitEvent = function() end

    G_reader_settings:save("autodim_starttime_minutes", 5)

    UIManager = require("ui/uimanager")
    UIManager:setRunForeverMode()

    UIManager:handleInput()
    UIManager:updateLastUserActionTime()
    UIManager:quit()

    requireBackgroundRunner()
    local Geom = require("ui/geometry")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    mock_ui = WidgetContainer:new({
      dimen = Geom:new({ w = 600, h = 800 }),
      menu = {
        registerToMainMenu = function() end,
      },
    })
    class = dofile("plugins/autodim.koplugin/main.lua")
    AutoDim = class:new({ ui = mock_ui })
    table.insert(mock_ui, AutoDim)
    UIManager:show(mock_ui)
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
  end)

  after_each(function()
    UIManager:close(mock_ui)
    AutoDim:onClose()
    MockTime:increase(2)
    UIManager:handleInput()
    AutoDim = nil
    mock_ui = nil
    stopBackgroundRunner()
    Device.isKindle:revert()
    Device.hasEinkScreen:revert()
    G_reader_settings:delete("autodim_starttime_minutes")
  end)

  it(
    "should not dim when idle time is less than configuration threshold",
    function()
      Device:getPowerDevice():setIntensity(10)

      MockTime:increase(240)
      UIManager:handleInput()

      assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
      assert.is_nil(AutoDim.trap_widget)
    end
  )

  it("should start dimming when idle time exceeds threshold", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()

    assert.is_not_nil(AutoDim.trap_widget)

    for i = 1, 9 do
      MockTime:increase(0.15)
      UIManager:handleInput()
    end

    assert.are.equal(1, Device:getPowerDevice():frontlightIntensity())
  end)

  it("should restore frontlight level on resume", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()

    for i = 1, 9 do
      MockTime:increase(0.15)
      UIManager:handleInput()
    end
    assert.are.equal(1, Device:getPowerDevice():frontlightIntensity())
    assert.is_not_nil(AutoDim.trap_widget)

    AutoDim:onResume()

    MockTime:increase(1)
    UIManager:handleInput()

    assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
    assert.is_nil(AutoDim.trap_widget)
  end)

  it("should handle frontlight turned off manually during dimming", function()
    Device:getPowerDevice():setIntensity(10)

    MockTime:increase(301)
    UIManager:handleInput()
    assert.is_not_nil(AutoDim.trap_widget)

    AutoDim:onFrontlightTurnedOff()

    assert.is_nil(AutoDim.trap_widget)
    assert.is_nil(AutoDim.origin_fl)
  end)

  it(
    "onDeviceIdling does nothing when AutoDim is disabled (autodim_starttime_m = -1)",
    function()
      AutoDim.autodim_starttime_m = -1
      AutoDim:onDeviceIdling()
      assert.is_nil(AutoDim.trap_widget)
    end
  )

  it(
    "broadcasts DeviceBusy exactly once on user action while idle, and never when not idle",
    function()
      local PluginShare = require("pluginshare")
      local events = {}
      local orig_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(self, ev)
        local name = type(ev) == "table" and (ev.handler and ev.handler:gsub("^on", "") or ev.action) or ev
        table.insert(events, name)
        return orig_broadcast(self, ev)
      end
      finally(function()
        UIManager.broadcastEvent = orig_broadcast
      end)

      -- 1. When not idle (UIManager.DeviceIdling is false)
      UIManager.DeviceIdling = false
      UIManager:updateLastUserActionTime()
      assert.are.equal(0, #events)

      -- 2. When idle (UIManager.DeviceIdling is true)
      UIManager.DeviceIdling = true
      UIManager:updateLastUserActionTime()
      assert.is_false(UIManager.DeviceIdling)
      assert.are.equal(1, #events)
      assert.are.equal("DeviceBusy", events[1])

      -- 3. Consecutive user action while already busy does not broadcast again
      UIManager:updateLastUserActionTime()
      assert.are.equal(1, #events)
    end
  )

  it(
    "_rampTask leaves trap_widget shown on user action until tap dismiss",
    function()
      Device:getPowerDevice():setIntensity(10)

      MockTime:increase(301)
      UIManager:handleInput()
      assert.is_not_nil(AutoDim.trap_widget)
      assert.is_true(UIManager.DeviceIdling)

      -- Touch-down bumps last user action time before tap dismiss
      UIManager:updateLastUserActionTime()
      assert.is_false(UIManager.DeviceIdling)

      local fl_after_busy = Device:getPowerDevice():frontlightIntensity()
      MockTime:increase(1)
      UIManager:handleInput()
      assert.are.equal(fl_after_busy, Device:getPowerDevice():frontlightIntensity())

      -- Tap dismiss restores intensity
      AutoDim.trap_widget:onTapDismiss()
      assert.is_nil(AutoDim.trap_widget)
      assert.are.equal(10, Device:getPowerDevice():frontlightIntensity())
    end
  )
end)
