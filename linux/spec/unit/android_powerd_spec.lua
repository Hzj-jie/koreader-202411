local BasePowerD = require("device/generic/powerd")

describe("AndroidPowerD", function()
  local AndroidPowerD
  local mock_android
  local mock_device, mock_powerd

  setup(function()
    require("commonrequire")

    mock_android = {
      screen_brightness = 100,
      screen_min_brightness = 0,
      screen_max_brightness = 255,
      screen_warmth = 50,
      screen_min_warmth = 0,
      screen_max_warmth = 100,
      battery_level = 90,
      is_charging = false,
      frontlight_switch_enabled = false,
      has_standalone_warmth = false,

      getScreenBrightness = function()
        return mock_android.screen_brightness
      end,
      setScreenBrightness = function(val)
        mock_android.screen_brightness = val
      end,
      getScreenMinBrightness = function()
        return mock_android.screen_min_brightness
      end,
      getScreenMaxBrightness = function()
        return mock_android.screen_max_brightness
      end,
      getScreenWarmth = function()
        return mock_android.screen_warmth
      end,
      setScreenWarmth = function(val)
        mock_android.screen_warmth = val
      end,
      getScreenMinWarmth = function()
        return mock_android.screen_min_warmth
      end,
      getScreenMaxWarmth = function()
        return mock_android.screen_max_warmth
      end,
      getBatteryLevel = function()
        return mock_android.battery_level
      end,
      isCharging = function()
        return mock_android.is_charging
      end,
      enableFrontlightSwitch = function()
        mock_android.frontlight_switch_enabled = true
      end,
      hasStandaloneWarmth = function()
        return mock_android.has_standalone_warmth
      end,
    }

    package.loaded["android"] = mock_android
    package.loaded["device/android/powerd"] = nil
    AndroidPowerD = require("device/android/powerd")
  end)

  before_each(function()
    mock_android.screen_brightness = 100
    mock_android.screen_min_brightness = 0
    mock_android.screen_max_brightness = 255
    mock_android.screen_warmth = 50
    mock_android.screen_min_warmth = 0
    mock_android.screen_max_warmth = 100
    mock_android.battery_level = 90
    mock_android.is_charging = false
    mock_android.frontlight_switch_enabled = false
    mock_android.has_standalone_warmth = false

    mock_device = {
      hasFrontlight = function()
        return true
      end,
      hasNaturalLight = function()
        return false
      end,
    }

    mock_powerd = AndroidPowerD:new({
      device = mock_device,
    })
  end)

  describe("Battery and charging telemetry", function()
    it("should query battery level and charging state", function()
      mock_android.battery_level = 78
      assert.are.equal(78, mock_powerd:getCapacityHW())

      mock_android.is_charging = true
      assert.is_true(mock_powerd:isChargingHW())

      mock_android.is_charging = false
      assert.is_false(mock_powerd:isChargingHW())
    end)
  end)

  describe("Frontlight intensity query and switch", function()
    it("should calculate intensity from screen brightness", function()
      -- bright_diff = 255. brightness = 127 -> 127 / 255 * 100 = 49
      mock_android.screen_brightness = 127
      assert.are.equal(49, mock_powerd:frontlightIntensityHW())
    end)

    it("should enable frontlight switch and set brightness", function()
      mock_powerd:setIntensityHW(50)
      assert.is_true(mock_android.frontlight_switch_enabled)
      -- 50 * 255 / 100 = 127
      assert.are.equal(127, mock_android.screen_brightness)
    end)
  end)

  describe("Brightness and warmth scaling", function()
    it(
      "setIntensityHW calculates brightness proportionally to bright_diff",
      function()
        mock_android.screen_min_brightness = 10
        mock_android.screen_max_brightness = 255
        mock_android.screen_brightness = 10

        local p = AndroidPowerD:new({
          device = {
            hasFrontlight = function()
              return true
            end,
            hasNaturalLight = function()
              return false
            end,
          },
        })

        -- When min_bright = 10 and max_bright = 255, bright_diff = 245.
        -- At intensity = 100, the brightness is math.floor(100 * 245 / 100) = 245.
        p:setIntensityHW(100)
        assert.are.equal(245, mock_android.screen_brightness)
      end
    )

    it(
      "setWarmthHW sets hardware warmth value directly",
      function()
        mock_android.screen_min_warmth = 0
        mock_android.screen_max_warmth = 10
        mock_android.screen_warmth = 0

        local p = AndroidPowerD:new({
          device = {
            hasFrontlight = function()
              return true
            end,
            hasNaturalLight = function()
              return true
            end,
          },
        })

        p:setWarmthHW(8)
        assert.are.equal(8, mock_android.screen_warmth)
      end
    )
  end)
end)
