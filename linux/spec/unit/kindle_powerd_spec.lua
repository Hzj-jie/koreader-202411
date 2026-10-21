local BasePowerD = require("device/generic/powerd")
local LibLipcs = require("liblipcs")
local WakeupMgr = require("device/wakeupmgr")
local ffiUtil = require("ffi/util")

describe("KindlePowerD", function()
  local KindlePowerD
  local mock_device, mock_powerd
  local mock_lipc
  local tmp_files = {}

  setup(function()
    require("commonrequire")
    KindlePowerD = require("device/kindle/powerd")
  end)

  local function create_temp_file(content)
    local path = "/tmp/test_kindle_" .. ffiUtil.getpid() .. "_" .. #tmp_files
    local f = io.open(path, "w")
    if content then
      f:write(content)
    end
    f:close()
    table.insert(tmp_files, path)
    return path
  end

  teardown(function()
    for _, path in ipairs(tmp_files) do
      os.remove(path)
    end
  end)

  before_each(function()
    mock_lipc = {
      props = {
        ["com.lab126.powerd:flIntensity"] = 10,
        ["com.lab126.powerd:currentAmberLevel"] = 0,
        ["com.lab126.powerd:battLevel"] = 100,
        ["com.lab126.powerd:isCharging"] = 0,
        ["com.lab126.powerd:state"] = "active",
      },
      get_int_property = function(self_l, bus, prop)
        return self_l.props[bus .. ":" .. prop]
      end,
      set_int_property = function(self_l, bus, prop, val)
        self_l.props[bus .. ":" .. prop] = val
      end,
      get_string_property = function(self_l, bus, prop)
        return self_l.props[bus .. ":" .. prop]
      end,
      set_string_property = function(self_l, bus, prop, val)
        self_l.props[bus .. ":" .. prop] = val
      end,
    }

    LibLipcs.accessor = function()
      return mock_lipc
    end
    LibLipcs.isFake = function(self_l, acc)
      return false
    end

    mock_device = {
      hasFrontlight = function()
        return true
      end,
      hasNaturalLight = function()
        return false
      end,
      canTurnFrontlightOff = function()
        return true
      end,
      supportsScreensaver = function()
        return true
      end,
      _beforeSuspend = function() end,
      _afterResume = function() end,
    }

    mock_powerd = KindlePowerD:new({
      device = mock_device,
      fl_intensity_file = create_temp_file("10"),
      batt_capacity_file = create_temp_file("85"),
      batt_status_file = create_temp_file("Full"),
      hall_file = create_temp_file("1"),
    })
  end)

  describe("Initialization and synthetic frontlight step", function()
    it("should keep fl_max as 24 when frontlight can be turned off", function()
      assert.are.equal(24, mock_powerd.fl_max)
    end)

    it(
      "should increment fl_max when frontlight cannot be turned off",
      function()
        local dev_no_off = {
          hasFrontlight = function()
            return true
          end,
          hasNaturalLight = function()
            return false
          end,
          canTurnFrontlightOff = function()
            return false
          end,
          supportsScreensaver = function()
            return true
          end,
        }
        local powerd_no_off = KindlePowerD:new({
          device = dev_no_off,
        })
        assert.are.equal(25, powerd_no_off.fl_max)
      end
    )
  end)

  describe("Frontlight intensity query and control", function()
    it("should return 0 when device has no frontlight", function()
      mock_device.hasFrontlight = function()
        return false
      end
      assert.are.equal(0, mock_powerd:frontlightIntensityHW())
    end)

    it(
      "should query lipc for frontlight intensity when device can turn off",
      function()
        mock_lipc.props["com.lab126.powerd:flIntensity"] = 15
        assert.are.equal(15, mock_powerd:frontlightIntensityHW())
        assert.is_true(mock_powerd:isFrontlightOnHW())
      end
    )

    it(
      "should handle synthetic step on devices that cannot turn off frontlight",
      function()
        mock_device.canTurnFrontlightOff = function()
          return false
        end

        -- Case 1: lipc is > 0 -> returns lipc + 1
        mock_lipc.props["com.lab126.powerd:flIntensity"] = 5
        assert.are.equal(6, mock_powerd:frontlightIntensityHW())

        -- Case 2: lipc is 0 and sysfs is 0 -> returns 0
        local f = io.open(mock_powerd.fl_intensity_file, "w")
        f:write("0")
        f:close()
        mock_lipc.props["com.lab126.powerd:flIntensity"] = 0
        assert.are.equal(0, mock_powerd:frontlightIntensityHW())

        -- Case 3: lipc is 0 but sysfs > 0 -> returns fl_min + 1 (1)
        f = io.open(mock_powerd.fl_intensity_file, "w")
        f:write("5")
        f:close()
        assert.are.equal(1, mock_powerd:frontlightIntensityHW())
      end
    )

    it("should set intensity via lipc and handle hardware turn off", function()
      mock_powerd:setIntensityHW(18)
      assert.are.equal(18, mock_lipc.props["com.lab126.powerd:flIntensity"])

      -- When canTurnFrontlightOff is false
      mock_device.canTurnFrontlightOff = function()
        return false
      end
      mock_powerd:setIntensityHW(10)
      assert.are.equal(9, mock_lipc.props["com.lab126.powerd:flIntensity"])

      mock_powerd:setIntensityHW(0)
      assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
      local f = io.open(mock_powerd.fl_intensity_file, "r")
      local val = f:read("*number")
      f:close()
      assert.are.equal(0, val)
    end)
  end)

  describe("Warmth, battery, and hall sensor", function()
    it("should query and set warmth", function()
      mock_lipc.props["com.lab126.powerd:currentAmberLevel"] = 12
      -- fromNativeWarmth maps 12 in [0..24] to 50 in [0..100]
      assert.are.equal(50, mock_powerd:frontlightWarmthHW())

      mock_powerd:setWarmthHW(16)
      assert.are.equal(
        16,
        mock_lipc.props["com.lab126.powerd:currentAmberLevel"]
      )
    end)

    it("should query battery level and charging status", function()
      mock_lipc.props["com.lab126.powerd:battLevel"] = 82
      mock_lipc.props["com.lab126.powerd:isCharging"] = 1
      assert.are.equal(82, mock_powerd:getCapacityHW())
      assert.is_true(mock_powerd:isChargingHW())

      mock_lipc.props["com.lab126.powerd:isCharging"] = 0
      assert.is_false(mock_powerd:isChargingHW())

      assert.is_true(mock_powerd:isChargedHW())
    end)

    it("should query and toggle hall effect sensor", function()
      assert.is_true(mock_powerd:hasHallSensor())
      assert.is_true(mock_powerd:isHallSensorEnabled())

      mock_powerd:onToggleHallSensor(false)
      assert.is_false(mock_powerd:isHallSensorEnabled())
      assert.is_false(
        G_reader_settings:read("kindle_hall_effect_sensor_enabled")
      )

      mock_powerd:onToggleHallSensor(true)
      assert.is_true(mock_powerd:isHallSensorEnabled())
      assert.is_true(
        G_reader_settings:read("kindle_hall_effect_sensor_enabled")
      )
    end)
  end)

  describe("Suspend and RTC wakeup management", function()
    it("should trigger power button suspend and query powerd state", function()
      mock_powerd:toggleSuspend()
      assert.are.equal(1, mock_lipc.props["com.lab126.powerd:powerButton"])

      mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
      assert.are.equal("screenSaver", mock_powerd:getPowerdState())
    end)

    it("should schedule RTC wakeup when alarm is in the future", function()
      local now = 1700000000
      local orig_time = os.time
      os.time = function()
        return now
      end
      finally(function()
        os.time = orig_time
      end)

      mock_powerd.device.wakeup_mgr:addTask(60, function() end)
      mock_powerd:readyToSuspend()

      assert.are.equal(60, mock_lipc.props["com.lab126.powerd:rtcWakeup"])
    end)
  end)

  describe("Suspend alarm cleanup", function()
    it(
      "readyToSuspend removes expired alarm task when alarm time is past",
      function()
        local current_time = 1700000000
        local orig_time = os.time
        os.time = function()
          return current_time
        end
        finally(function()
          os.time = orig_time
        end)

        mock_powerd.device.wakeup_mgr:addTask(10, function() end)
        current_time = 1700000015

        mock_powerd:readyToSuspend()
        assert.is_false(mock_powerd.device.wakeup_mgr:isWakeupAlarmScheduled())
      end
    )
  end)
end)
