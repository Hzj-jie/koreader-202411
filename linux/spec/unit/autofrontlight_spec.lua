describe("AutoFrontlight widget tests", function()
  local Device, PowerD, MockTime, class, AutoFrontlight, UIManager

  local function setAmbientBrightnessAndRun(brightness)
    Device.brightness = brightness
    MockTime:increase(2)
    UIManager:handleInput()
  end

  local function assertFrontlightLevel(expected)
    assert.are.equal(expected, Device:getPowerDevice().frontlight)
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    MockTime = require("mock_time")
    MockTime:install()

    PowerD = require("device/generic/powerd"):new({
      frontlight = 0,
    })
    PowerD.frontlightIntensityHW = function()
      return 2
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
    Device.isKindle = function()
      return true
    end
    Device.model = "KindleVoyage"
    Device.brightness = 0
    Device.hasFrontlight = function()
      return true
    end
    Device.hasLightSensor = function()
      return true
    end
    Device.powerd = PowerD:new({
      device = Device,
    })
    Device.ambientBrightnessLevel = function(self)
      return self.brightness
    end
    Device.input.waitEvent = function() end
    require("luasettings")
      :open(require("datastorage"):getSettingsDir() .. "/autofrontlight.lua")
      :save("enable", true)
      :close()

    UIManager = require("ui/uimanager")
    UIManager:setRunForeverMode()

    requireBackgroundRunner()
    class = dofile("plugins/autofrontlight.koplugin/main.lua")
    AutoFrontlight = class:new()
    notifyBackgroundJobsUpdated()

    -- Ensure the background runner has succeeded set the job.insert_sec.
    MockTime:increase(2)
    UIManager:handleInput()
  end)

  after_each(function()
    AutoFrontlight:onClose()
    -- Ensure the scheduled task from this test case won't impact others.
    MockTime:increase(2)
    UIManager:handleInput()
    AutoFrontlight = nil
    stopBackgroundRunner()
  end)

  it("should automatically turn on or off frontlight", function()
    -- Set the initial state to AutoFrontlight widget.
    setAmbientBrightnessAndRun(0)

    setAmbientBrightnessAndRun(3)
    assertFrontlightLevel(0)
    setAmbientBrightnessAndRun(0)
    assertFrontlightLevel(2)
    setAmbientBrightnessAndRun(1)
    assertFrontlightLevel(2)
    setAmbientBrightnessAndRun(2)
    assertFrontlightLevel(2)
    setAmbientBrightnessAndRun(3)
    assertFrontlightLevel(0)
    setAmbientBrightnessAndRun(4)
    assertFrontlightLevel(0)
    setAmbientBrightnessAndRun(3)
    assertFrontlightLevel(0)
    setAmbientBrightnessAndRun(2)
    assertFrontlightLevel(0)
    setAmbientBrightnessAndRun(1)
    assertFrontlightLevel(2)
    setAmbientBrightnessAndRun(0)
    assertFrontlightLevel(2)
  end)

  it("should turn on frontlight at the beginning", function()
    -- Set the initial state to AutoFrontlight widget.
    setAmbientBrightnessAndRun(3)

    Device:getPowerDevice():turnOffFrontlight()
    setAmbientBrightnessAndRun(0)
    assertFrontlightLevel(2)
  end)

  it("should turn off frontlight at the beginning", function()
    -- Set the initial state to AutoFrontlight widget.
    setAmbientBrightnessAndRun(0)

    Device:getPowerDevice():turnOnFrontlight()
    setAmbientBrightnessAndRun(3)
    assertFrontlightLevel(0)
  end)

  it("should handle configuration update", function()
    -- Set the initial state to AutoFrontlight widget.
    setAmbientBrightnessAndRun(3)

    Device:getPowerDevice():turnOffFrontlight()
    setAmbientBrightnessAndRun(0)
    assertFrontlightLevel(2)
    AutoFrontlight:flipSetting()
    -- The last AutoFrontlight job is in the queue and will be executed first before the flipped setting to take effect.
    setAmbientBrightnessAndRun(0)
    setAmbientBrightnessAndRun(3)
    assertFrontlightLevel(2)
  end)

  it(
    "should return { disabled = true } when Device.isEmulator() and Device:isKindle() are false",
    function()
      local orig_isEmulator = Device.isEmulator
      local orig_isKindle = Device.isKindle

      Device.isEmulator = function()
        return false
      end
      Device.isKindle = function()
        return false
      end

      package.loaded["plugins/autofrontlight.koplugin/main"] = nil
      local res = dofile("plugins/autofrontlight.koplugin/main.lua")

      assert.are.same({ disabled = true }, res)

      Device.isEmulator = orig_isEmulator
      Device.isKindle = orig_isKindle
    end
  )

  it(
    "respects manual frontlight toggle when ambient brightness is unchanged",
    function()
      -- Set the initial state: ambient brightness 0, frontlight on (level 2)
      setAmbientBrightnessAndRun(3)
      Device:getPowerDevice():turnOffFrontlight()
      setAmbientBrightnessAndRun(0)
      assertFrontlightLevel(2)

      -- User turns off frontlight manually while still in dark environment
      Device:getPowerDevice():turnOffFrontlight()
      assertFrontlightLevel(0)

      -- When AutoFrontlight runs again in ambient brightness 0, it should respect
      -- the manual toggle because ambient brightness is unchanged
      setAmbientBrightnessAndRun(0)
      assertFrontlightLevel(0)
    end
  )

  it(
    "main.lua calls Device:isEmulator() with colon syntax passing self",
    function()
      -- Bug: line 4 calls `Device.isEmulator()` with dot syntax instead of `Device:isEmulator()`.
      -- If isEmulator expects self, calling Device.isEmulator() passes self as nil.
      local orig_isEmulator = Device.isEmulator
      local called_with_self = false
      Device.isEmulator = function(self)
        if self ~= nil then
          called_with_self = true
          return true
        end
        return false
      end

      package.loaded["plugins/autofrontlight.koplugin/main"] = nil
      dofile("plugins/autofrontlight.koplugin/main.lua")

      assert.is_true(
        called_with_self,
        "Device:isEmulator() should be called with colon syntax passing self"
      )
      Device.isEmulator = orig_isEmulator
    end
  )
end)
