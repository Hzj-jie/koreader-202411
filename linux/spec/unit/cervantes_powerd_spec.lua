-- luacheck: ignore 122
require("commonrequire")
local CervantesPowerD = require("device/cervantes/powerd")

describe("CervantesPowerD", function()
  local mock_device
  local mock_fl
  local powerd
  local status_content = "Discharging"
  local capacity_content = 80
  local events_broadcast = {}
  local brightness_set = nil
  local natural_brightness_set = nil
  local orig_open = io.open

  before_each(function()
    status_content = "Discharging"
    capacity_content = 80
    events_broadcast = {}
    brightness_set = nil
    natural_brightness_set = nil

    mock_fl = {
      setBrightness = function(self, val)
        brightness_set = val
      end,
      setNaturalBrightness = function(self, intensity, warmth)
        natural_brightness_set = { intensity = intensity, warmth = warmth }
      end,
      setWarmth = function(self, val) end,
    }

    mock_device = {
      hasFrontlight = function()
        return true
      end,
      hasNaturalLight = function()
        return false
      end,
      hasNaturalLightMixer = function()
        return false
      end,
      disableKeyRepeat = function() end,
      restoreKeyRepeat = function() end,
      last_suspend_at = 0,
      last_resume_at = 0,
      total_suspend_time = 0,
      frontlight_settings = {},
    }

    io.open = function(path, mode)
      if path == "/tmp/mock_cervantes_capacity" then
        return {
          read = function(self, fmt)
            return capacity_content
          end,
          close = function(self) end,
        }
      elseif path == "/tmp/mock_cervantes_status" then
        return {
          read = function(self, fmt)
            return status_content
          end,
          close = function(self) end,
        }
      end
      return orig_open(path, mode)
    end

    powerd = CervantesPowerD:new({
      device = mock_device,
      capacity_file = "/tmp/mock_cervantes_capacity",
      status_file = "/tmp/mock_cervantes_status",
    })
    powerd.fl = mock_fl
    powerd:UIManagerReady({
      flushSettings = function() end,
      broadcastEvent = function(_self, ev)
        table.insert(events_broadcast, ev.handler)
      end,
      updateLastUserActionTime = function() end,
    })
  end)

  after_each(function()
    io.open = orig_open
    G_reader_settings:delete("frontlight_intensity")
    G_reader_settings:delete("is_frontlight_on")
    G_reader_settings:delete("frontlight_warmth")
  end)

  describe("battery status and capacity", function()
    it("reads battery capacity from sysfs", function()
      capacity_content = 77
      assert.are.equal(77, powerd:getCapacityHW())
    end)

    it("checks charging state from sysfs", function()
      status_content = "Charging"
      assert.is_true(powerd:isChargingHW())

      status_content = "Discharging"
      assert.is_false(powerd:isChargingHW())
    end)
  end)

  describe("suspend and resume lifecycle", function()
    it("zeros brightness and broadcasts Suspend before suspend", function()
      powerd.hw_intensity = 45
      powerd:beforeSuspend()
      assert.are.same({ "onSuspend" }, events_broadcast)
      assert.are.equal(0, brightness_set)
    end)

    it(
      "restores hardware intensity and broadcasts Resume after resume",
      function()
        powerd.hw_intensity = 45
        powerd:afterResume()
        assert.are.same({ "onResume" }, events_broadcast)
        assert.are.equal(45, brightness_set)
      end
    )

    it("restores natural brightness when device has natural light", function()
      mock_device.hasNaturalLight = function()
        return true
      end
      powerd.hw_intensity = 60
      powerd.fl_warmth = 35
      powerd:afterResume()
      assert.are.same({ "onResume" }, events_broadcast)
      assert.are.equal(60, natural_brightness_set.intensity)
      assert.are.equal(35, natural_brightness_set.warmth)
    end)

    it("restores hardware intensity even if fl_was_on was false", function()
      powerd.fl_was_on = false
      powerd.hw_intensity = 30
      brightness_set = nil
      powerd:afterResume()
      assert.are.same({ "onResume" }, events_broadcast)
      assert.are.equal(30, brightness_set)
    end)
  end)

  describe("settings persistence", function()
    it("saves frontlight intensity and state into G_reader_settings", function()
      powerd.fl_intensity = 70
      powerd.is_fl_on = true
      powerd.fl_warmth = 25
      powerd:saveSettings()

      assert.are.equal(70, G_reader_settings:read("frontlight_intensity"))
      assert.is_true(G_reader_settings:read("is_frontlight_on"))
      assert.are.equal(25, G_reader_settings:read("frontlight_warmth"))
    end)
  end)

  describe("startup light sync", function()
    it("_syncLightOnStart synchronizes saved frontlight state", function()
      G_reader_settings:save("is_frontlight_on", true)
      G_reader_settings:save("frontlight_intensity", 50)

      powerd:_syncLightOnStart()

      assert.is_true(powerd.initial_is_fl_on)
      assert.are.equal(50, powerd.hw_intensity)
    end)
  end)
end)
