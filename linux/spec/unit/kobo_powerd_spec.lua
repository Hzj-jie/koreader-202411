local BasePowerD = require("device/generic/powerd")
local NickelConf = require("device/kobo/nickel_conf")
local ffiUtil = require("ffi/util")

describe("KoboPowerD", function()
  local KoboPowerD
  local mock_device, mock_powerd
  local tmp_conf

  setup(function()
    require("commonrequire")
    KoboPowerD = require("device/kobo/powerd")

    tmp_conf = "/tmp/test_kobo_conf_" .. ffiUtil.getpid() .. ".conf"
    local f = io.open(tmp_conf, "w")
    f:write(
      "[PowerOptions]\nFrontLightLevel=50\nFrontLightState=true\nColorSetting=3000\n"
    )
    f:close()
    if NickelConf._set_kobo_conf_path then
      NickelConf._set_kobo_conf_path(tmp_conf)
    end
  end)

  teardown(function()
    if tmp_conf then
      os.remove(tmp_conf)
    end
  end)

  before_each(function()
    mock_device = {
      hasFrontlight = function()
        return false
      end,
      hasNaturalLight = function()
        return false
      end,
      hasNaturalLightMixer = function()
        return false
      end,
      hasAuxBattery = function()
        return true
      end,
      frontlight_settings = {},
    }

    mock_powerd = KoboPowerD:new({
      device = mock_device,
      battery_sysfs = "/sys/class/power_supply/mc13892_bat",
      aux_battery_sysfs = "/sys/class/power_supply/bd71827_bat",
    })
  end)

  describe("Light synchronization on startup", function()
    it(
      "should set fixed intensity when KOBO_LIGHT_ON_START is positive",
      function()
        local orig_read = G_defaults.read
        G_defaults.read = function(self_d, key)
          if key == "KOBO_LIGHT_ON_START" then
            return "45"
          end
          return orig_read(self_d, key)
        end
        finally(function()
          G_defaults.read = orig_read
        end)

        mock_powerd:_syncKoboLightOnStart()
        assert.are.equal(45, mock_powerd.hw_intensity)
        assert.is_true(mock_powerd.initial_is_fl_on)
      end
    )

    it("should turn off light when KOBO_LIGHT_ON_START is zero", function()
      local orig_read = G_defaults.read
      G_defaults.read = function(self_d, key)
        if key == "KOBO_LIGHT_ON_START" then
          return "0"
        end
        return orig_read(self_d, key)
      end
      finally(function()
        G_defaults.read = orig_read
      end)

      mock_powerd:_syncKoboLightOnStart()
      assert.are.equal(1, mock_powerd.hw_intensity)
      assert.is_false(mock_powerd.initial_is_fl_on)
    end)

    it(
      "should restore settings from G_reader_settings when KOBO_LIGHT_ON_START is -1",
      function()
        local orig_defaults = G_defaults.read
        local orig_settings = G_reader_settings.read
        G_defaults.read = function(self_d, key)
          if key == "KOBO_LIGHT_ON_START" then
            return "-1"
          end
          return orig_defaults(self_d, key)
        end
        G_reader_settings.read = function(self_s, key)
          if key == "frontlight_intensity" then
            return 33
          elseif key == "is_frontlight_on" then
            return true
          elseif key == "frontlight_warmth" then
            return 50
          end
          return orig_settings(self_s, key)
        end
        finally(function()
          G_defaults.read = orig_defaults
          G_reader_settings.read = orig_settings
        end)

        mock_powerd.fl_warmth = 0
        mock_powerd:_syncKoboLightOnStart()
        assert.are.equal(33, mock_powerd.hw_intensity)
        assert.is_true(mock_powerd.initial_is_fl_on)
        assert.are.equal(50, mock_powerd.fl_warmth)
      end
    )

    it(
      "should read intensity and warmth from NickelConf when KOBO_LIGHT_ON_START is -2",
      function()
        local orig_defaults = G_defaults.read
        local orig_get_level = NickelConf.frontLightLevel.get
        local orig_get_state = NickelConf.frontLightState.get
        local orig_get_color = NickelConf.colorSetting.get

        G_defaults.read = function(self_d, key)
          if key == "KOBO_LIGHT_ON_START" then
            return "-2"
          end
          return orig_defaults(self_d, key)
        end
        NickelConf.frontLightLevel.get = function()
          return 60
        end
        NickelConf.frontLightState.get = function()
          return true
        end
        NickelConf.colorSetting.get = function()
          return 3950 -- ~50% warmth
        end

        finally(function()
          G_defaults.read = orig_defaults
          NickelConf.frontLightLevel.get = orig_get_level
          NickelConf.frontLightState.get = orig_get_state
          NickelConf.colorSetting.get = orig_get_color
        end)

        mock_powerd.fl_warmth = 0
        mock_powerd:_syncKoboLightOnStart()
        assert.are.equal(60, mock_powerd.hw_intensity)
        assert.is_true(mock_powerd.initial_is_fl_on)
        assert.are.equal(50, mock_powerd.fl_warmth)
      end
    )
  end)

  describe("Auxiliary battery methods", function()
    it(
      "should query auxiliary battery capacity, connection, and charging status",
      function()
        mock_powerd:init()

        mock_powerd.unchecked_read_int_file = function(self_p, path)
          if
            path == "/sys/class/power_supply/bd71827_bat/cilix_bat_capacity"
          then
            return 85
          end
        end
        mock_powerd.read_int_file = function(self_p, path)
          if path == "/sys/class/power_supply/bd71827_bat/cilix_conn" then
            return 1
          elseif
            path == "/sys/class/power_supply/bd71827_bat/charge_status"
          then
            return 3
          end
          return 0
        end

        assert.are.equal(85, mock_powerd:getAuxCapacityHW())
        assert.is_true(mock_powerd:isAuxBatteryConnectedHW())
        assert.is_true(mock_powerd:isAuxChargingHW())
        assert.is_true(mock_powerd:isAuxChargedHW())
      end
    )
  end)

  describe("Frontlight and warmth control", function()
    it("should return and update frontlight intensity and warmth", function()
      mock_powerd.device.hasFrontlight = function()
        return true
      end
      mock_powerd.device.hasNaturalLightMixer = function()
        return true
      end

      mock_powerd.hw_intensity = 40
      mock_powerd.fl_warmth = 25

      assert.are.equal(40, mock_powerd:frontlightIntensityHW())
      assert.are.equal(25, mock_powerd:frontlightWarmthHW())

      local mock_fl = {
        setBrightness = function(self_fl, val)
          mock_powerd.brightness_set = val
        end,
        setWarmth = function(self_fl, val)
          mock_powerd.fl_warmth = val
          mock_powerd.warmth_set = val
        end,
        setNaturalBrightness = function(self_fl, val)
          mock_powerd.warmth_set = val
        end,
      }
      mock_powerd.fl = mock_fl

      mock_powerd:setIntensityHW(70)
      assert.are.equal(70, mock_powerd.hw_intensity)
      assert.are.equal(70, mock_powerd.brightness_set)

      mock_powerd:setWarmthHW(80)
      assert.are.equal(80, mock_powerd.warmth_set)
    end)
  end)

  describe("saveSettings", function()
    it(
      "should persist intensity and sync with NickelConf when enabled",
      function()
        local orig_read = G_defaults.read
        local saved_settings = {}
        local nickel_saved = {}

        G_defaults.read = function(self_d, key)
          if key == "KOBO_SYNC_BRIGHTNESS_WITH_NICKEL" then
            return true
          end
          return orig_read(self_d, key)
        end

        local orig_save = G_reader_settings.save
        G_reader_settings.save = function(self_s, key, val)
          saved_settings[key] = val
        end

        local orig_state_get = NickelConf.frontLightState.get
        local orig_state_set = NickelConf.frontLightState.set
        local orig_level_get = NickelConf.frontLightLevel.get
        local orig_level_set = NickelConf.frontLightLevel.set

        NickelConf.frontLightState.get = function()
          return false
        end
        NickelConf.frontLightState.set = function(val)
          nickel_saved.state = val
        end
        NickelConf.frontLightLevel.get = function()
          return 0
        end
        NickelConf.frontLightLevel.set = function(val)
          nickel_saved.level = val
        end

        finally(function()
          G_defaults.read = orig_read
          G_reader_settings.save = orig_save
          NickelConf.frontLightState.get = orig_state_get
          NickelConf.frontLightState.set = orig_state_set
          NickelConf.frontLightLevel.get = orig_level_get
          NickelConf.frontLightLevel.set = orig_level_set
        end)

        mock_powerd.device.hasFrontlight = function()
          return true
        end
        mock_powerd.fl_intensity = 55
        mock_powerd.is_fl_on = true
        mock_powerd.fl_warmth = nil

        mock_powerd:saveSettings()
        assert.are.equal(55, saved_settings["frontlight_intensity"])
        assert.is_true(saved_settings["is_frontlight_on"])
        assert.is_true(nickel_saved.state)
        assert.are.equal(55, nickel_saved.level)
      end
    )
  end)

end)
