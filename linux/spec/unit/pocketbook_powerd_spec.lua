-- luacheck: ignore 122
local ffi = require("ffi")
local orig_load = ffi.load

local frontlight_state = 50
local frontlight_color = -1
local frontlight_enabled = 1
local set_fl_state_val = nil
local set_fl_color_val = nil
local set_fl_enabled_val = nil
local v2_enabled_exists = true
local battery_power = 85
local is_charging_val = 1

local mock_inkview = {
  GetFrontlightState = function()
    return frontlight_state
  end,
  SetFrontlightState = function(val)
    set_fl_state_val = val
  end,
  GetFrontlightColor = function()
    return frontlight_color
  end,
  SetFrontlightColor = function(val)
    set_fl_color_val = val
    return 0
  end,
  GetFrontlightEnabled = function()
    if not v2_enabled_exists then
      error("v1 inkview does not support GetFrontlightEnabled")
    end
    return frontlight_enabled
  end,
  SetFrontlightEnabled = function(val)
    if not v2_enabled_exists then
      error("v1 inkview does not support SetFrontlightEnabled")
    end
    set_fl_enabled_val = val
  end,
  GetBatteryPower = function()
    return battery_power
  end,
  IsCharging = function()
    return is_charging_val
  end,
}

ffi.load = function(name, global)
  if name == "inkview" then
    return mock_inkview
  end
  return orig_load(name, global)
end

require("commonrequire")
package.loaded["device/pocketbook/powerd"] = nil
local PocketBookPowerD = require("device/pocketbook/powerd")

describe("PocketBookPowerD", function()
  teardown(function()
    ffi.load = orig_load
  end)

  local mock_device
  local powerd
  local before_suspend_called = false
  local after_resume_called = false

  before_each(function()
    frontlight_state = 50
    frontlight_color = 30
    frontlight_enabled = 1
    set_fl_state_val = nil
    set_fl_color_val = nil
    set_fl_enabled_val = nil
    v2_enabled_exists = true
    battery_power = 85
    is_charging_val = 1
    before_suspend_called = false
    after_resume_called = false

    mock_device = {
      hasFrontlight = function()
        return true
      end,
      hasNaturalLight = function()
        return true
      end,
      _beforeSuspend = function()
        before_suspend_called = true
      end,
      _afterResume = function()
        after_resume_called = true
      end,
    }

    powerd = PocketBookPowerD:new({
      device = mock_device,
    })
  end)

  describe("battery and hardware status", function()
    it("reports battery capacity from inkview", function()
      battery_power = 92
      assert.are.equal(92, powerd:getCapacityHW())
    end)

    it("reports charging status from inkview", function()
      is_charging_val = 1
      assert.is_true(powerd:isChargingHW())

      is_charging_val = 0
      assert.is_false(powerd:isChargingHW())
    end)

    it("delegates suspend and resume notifications to device", function()
      powerd:beforeSuspend()
      assert.is_true(before_suspend_called)

      powerd:afterResume()
      assert.is_true(after_resume_called)
    end)
  end)

  describe("frontlight intensity and warmth control", function()
    it("queries frontlight intensity and updates internal cache", function()
      frontlight_state = 75
      frontlight_color = 40
      local intensity = powerd:frontlightIntensityHW()
      assert.are.equal(75, intensity)
      assert.are.equal(75, powerd.fl_intensity)
      assert.are.equal(40, powerd.fl_warmth)
    end)

    it("sets frontlight intensity using v2 api when available", function()
      v2_enabled_exists = true
      powerd:setIntensityHW(80)
      assert.are.equal(1, set_fl_enabled_val)
      assert.are.equal(80, set_fl_state_val)

      powerd:setIntensityHW(0)
      assert.are.equal(0, set_fl_enabled_val)
    end)

    it(
      "sets frontlight intensity using v1 api fallback when intensity is 0",
      function()
        v2_enabled_exists = false
        powerd:setIntensityHW(0)
        assert.are.equal(-1, set_fl_state_val)
      end
    )

    it("sets warmth level via inkview.SetFrontlightColor", function()
      powerd:setWarmthHW(65)
      assert.are.equal(65, set_fl_color_val)
    end)

    it("reports isFrontlightOn correctly with v2 api", function()
      v2_enabled_exists = true
      frontlight_enabled = 1
      assert.is_true(powerd:isFrontlightOn())

      frontlight_enabled = 0
      assert.is_false(powerd:isFrontlightOn())
    end)

    it(
      "frontlightWarmthHW returns inkview GetFrontlightColor directly",
      function()
        frontlight_color = -1
        assert.are.equal(-1, powerd:frontlightWarmthHW())
        frontlight_color = 50
        assert.are.equal(50, powerd:frontlightWarmthHW())
      end
    )

    it("reports isFrontlightOn correctly with v1 api", function()
      v2_enabled_exists = false
      frontlight_state = 50
      assert.is_true(powerd:isFrontlightOn())

      frontlight_state = 0
      assert.is_true(powerd:isFrontlightOn())

      frontlight_state = -1
      assert.is_false(powerd:isFrontlightOn())
    end)
  end)
end)
