local BasePowerD = require("device/generic/powerd")
local Device = require("device/generic/device")
local LibLipcs = require("liblipcs")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")

describe("KindlePowerD", function()
  local KindlePowerD
  local mock_device, mock_powerd
  local mock_lipc, mock_uimgr
  local orig_write_to_sysfs
  local sys_ops
  local tmp_files = {}
  local hall_dir = "/tmp/test_kindle_hall_" .. ffiUtil.getpid()
  local hall_enable_file = hall_dir .. "/hall_enable"
  local hall_trig_file = hall_dir .. "/hall_trig_wkup"

  setup(function()
    require("commonrequire")
    KindlePowerD = require("device/kindle/powerd")
    lfs.mkdir(hall_dir)
  end)

  local function write_file(path, content)
    local f = io.open(path, "w")
    if content then
      f:write(content)
    end
    f:close()
  end

  local function create_temp_file(content)
    local path = "/tmp/test_kindle_" .. ffiUtil.getpid() .. "_" .. #tmp_files
    write_file(path, content)
    table.insert(tmp_files, path)
    return path
  end

  teardown(function()
    for _, path in ipairs(tmp_files) do
      os.remove(path)
    end
    os.remove(hall_enable_file)
    os.remove(hall_trig_file)
    lfs.rmdir(hall_dir)
  end)

  before_each(function()
    sys_ops = {}
    orig_write_to_sysfs = ffiUtil.writeToSysfs
    ffiUtil.writeToSysfs = function(val, path)
      table.insert(sys_ops, { op = "sysfs", path = path, val = val })
      if path == "/sys/power/state" then
        return true
      end
      return orig_write_to_sysfs(val, path)
    end

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
        table.insert(sys_ops, { op = "lipc", prop = prop, val = val })
      end,
      get_string_property = function(self_l, bus, prop)
        return self_l.props[bus .. ":" .. prop]
      end,
      set_string_property = function(self_l, bus, prop, val)
        self_l.props[bus .. ":" .. prop] = val
        table.insert(sys_ops, { op = "lipc", prop = prop, val = val })
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
      sysfsSuspend = Device.sysfsSuspend,
      disableKeyRepeat = function() end,
      restoreKeyRepeat = function() end,
      last_suspend_at = 0,
      last_resume_at = 0,
      total_suspend_time = 0,
    }

    mock_uimgr = {
      scheduled = {},
      ticks = {},
      flushSettings = function() end,
      broadcastEvent = function() end,
      updateLastUserActionTime = function() end,
      scheduleIn = function(self_u, delay, fn, arg)
        table.insert(self_u.scheduled, { delay = delay, fn = fn, arg = arg })
      end,
      tickAfterNext = function(self_u, fn)
        table.insert(self_u.ticks, fn)
      end,
    }

    write_file(hall_enable_file, "1")
    write_file(hall_trig_file, "0")

    mock_powerd = KindlePowerD:new({
      device = mock_device,
      fl_intensity_file = create_temp_file("10"),
      batt_capacity_file = create_temp_file("85"),
      batt_status_file = create_temp_file("Full"),
      hall_file = hall_enable_file,
    })
    mock_powerd:UIManagerReady(mock_uimgr)
  end)

  after_each(function()
    ffiUtil.writeToSysfs = orig_write_to_sysfs
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

  describe("Suspend and powerd state", function()
    it("should trigger power button suspend and query powerd state", function()
      mock_powerd:toggleSuspend()
      assert.are.equal(1, mock_lipc.props["com.lab126.powerd:powerButton"])

      mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
      assert.are.equal("screenSaver", mock_powerd:getPowerdState())
    end)
  end)

  describe("Disabled Hall sensor wakeup handling", function()
    local function flush_ticks()
      while #mock_uimgr.ticks > 0 do
        table.remove(mock_uimgr.ticks, 1)()
      end
    end

    local function new_powerd_no_off()
      mock_device.canTurnFrontlightOff = function()
        return false
      end
      local powerd = KindlePowerD:new({
        device = mock_device,
        fl_intensity_file = create_temp_file("10"),
        batt_capacity_file = create_temp_file("85"),
        batt_status_file = create_temp_file("Full"),
        hall_file = hall_enable_file,
      })
      powerd:UIManagerReady(mock_uimgr)
      return powerd
    end

    it(
      "turns off frontlight before suspending to mem when hall_enable is 0, hall_trig_wkup is 1, and state is screenSaver",
      function()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(mock_powerd:isFrontlightOn())
        assert.are.equal(10, mock_powerd.fl_intensity)
        assert.are.same({
          { op = "lipc", prop = "flIntensity", val = 0 },
          { op = "sysfs", path = "/sys/power/state", val = "mem" },
        }, sys_ops)
      end
    )

    it(
      "writes 0 to sysfs intensity file before mem on devices that cannot turn frontlight off via lipc",
      function()
        local powerd_no_off = new_powerd_no_off()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        powerd_no_off:wakeupFromSuspend()

        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(powerd_no_off:isFrontlightOn())
        assert.are.equal(11, powerd_no_off.fl_intensity)
        assert.are.same({
          { op = "lipc", prop = "flIntensity", val = 0 },
          { op = "sysfs", path = powerd_no_off.fl_intensity_file, val = 0 },
          { op = "sysfs", path = "/sys/power/state", val = "mem" },
        }, sys_ops)
      end
    )

    it(
      "writes mem without touching frontlight when device has no frontlight",
      function()
        mock_device.hasFrontlight = function()
          return false
        end
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({
          { op = "sysfs", path = "/sys/power/state", val = "mem" },
        }, sys_ops)
      end
    )

    it(
      "does not touch frontlight or mem when hall_enable is 1",
      function()
        write_file(hall_enable_file, "1")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)
      end
    )

    it(
      "does not touch frontlight or mem when hall_trig_wkup is 0",
      function()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "0")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)
      end
    )

    it(
      "does not touch frontlight or mem when state is active or suspended",
      function()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "active"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)

        mock_lipc.props["com.lab126.powerd:state"] = "suspended"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)
      end
    )

    it(
      "does not crash or suspend when hall_file is nil",
      function()
        mock_powerd.hall_file = nil
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)
      end
    )

    it(
      "reads 0 and does not suspend when hall_trig_wkup file is missing",
      function()
        write_file(hall_enable_file, "0")
        os.remove(hall_trig_file)
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        mock_powerd:wakeupFromSuspend()

        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.are.same({}, sys_ops)
      end
    )

    it(
      "turns off frontlight and writes mem on Special Offers devices",
      function()
        mock_device.supportsScreensaver = function()
          return false
        end
        local powerd_so = KindlePowerD:new({
          device = mock_device,
          fl_intensity_file = create_temp_file("10"),
          batt_capacity_file = create_temp_file("85"),
          batt_status_file = create_temp_file("Full"),
          hall_file = hall_enable_file,
        })
        powerd_so:UIManagerReady(mock_uimgr)

        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"
        sys_ops = {}

        powerd_so:wakeupFromSuspend()

        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(powerd_so:isFrontlightOn())
        assert.are.same({
          { op = "lipc", prop = "flIntensity", val = 0 },
          { op = "sysfs", path = "/sys/power/state", val = "mem" },
        }, sys_ops)
      end
    )

    it(
      "preserves is_fl_on across disabled-Hall wakeup and restores frontlight on afterResume",
      function()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"

        mock_powerd:wakeupFromSuspend()
        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(mock_powerd:isFrontlightOn())

        mock_powerd:afterResume()
        flush_ticks()
        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(mock_powerd:isFrontlightOn())
      end
    )

    it(
      "preserves is_fl_on and restores synthetic step on afterResume when canTurnFrontlightOff is false",
      function()
        local powerd_no_off = new_powerd_no_off()
        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"

        powerd_no_off:wakeupFromSuspend()
        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(powerd_no_off:isFrontlightOn())

        powerd_no_off:afterResume()
        flush_ticks()
        assert.are.equal(10, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_true(powerd_no_off:isFrontlightOn())
      end
    )

    it(
      "keeps frontlight off on afterResume when frontlight was off before disabled-Hall wakeup",
      function()
        mock_powerd:setIntensityHW(0)
        assert.is_false(mock_powerd:isFrontlightOn())

        write_file(hall_enable_file, "0")
        write_file(hall_trig_file, "1")
        mock_lipc.props["com.lab126.powerd:state"] = "screenSaver"

        mock_powerd:wakeupFromSuspend()
        assert.is_false(mock_powerd:isFrontlightOn())

        mock_powerd:afterResume()
        flush_ticks()
        assert.are.equal(0, mock_lipc.props["com.lab126.powerd:flIntensity"])
        assert.is_false(mock_powerd:isFrontlightOn())
      end
    )
  end)
end)
