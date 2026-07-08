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
    class = dofile("plugins/autodim.koplugin/main.lua")
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    AutoDim = class:new({ ui = mock_ui })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
  end)

  after_each(function()
    AutoDim:onClose()
    MockTime:increase(2)
    UIManager:handleInput()
    AutoDim = nil
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
end)
