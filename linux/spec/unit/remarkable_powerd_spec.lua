-- luacheck: ignore 122
require("commonrequire")
local Remarkable_PowerD = require("device/remarkable/powerd")

describe("Remarkable_PowerD", function()
  local mock_device
  local powerd
  local status_content = "Discharging"
  local capacity_content = 80
  local before_suspend_called = false
  local after_resume_called = false
  local orig_open = io.open

  before_each(function()
    status_content = "Discharging"
    capacity_content = 80
    before_suspend_called = false
    after_resume_called = false

    mock_device = {
      hasFrontlight = function()
        return false
      end,
      hasNaturalLight = function()
        return false
      end,
      _beforeSuspend = function()
        before_suspend_called = true
      end,
      _afterResume = function()
        after_resume_called = true
      end,
    }

    io.open = function(path, mode)
      if path == "/tmp/mock_capacity" then
        return {
          read = function(self, fmt)
            return capacity_content
          end,
          close = function(self) end,
        }
      elseif path == "/tmp/mock_status" then
        return {
          read = function(self, fmt)
            return status_content
          end,
          close = function(self) end,
        }
      end
      return orig_open(path, mode)
    end

    powerd = Remarkable_PowerD:new({
      device = mock_device,
      capacity_file = "/tmp/mock_capacity",
      status_file = "/tmp/mock_status",
    })
  end)

  after_each(function()
    io.open = orig_open
  end)

  describe("capacity and frontlight", function()
    it("reads battery capacity from sysfs capacity file", function()
      capacity_content = 95
      assert.are.equal(95, powerd:getCapacityHW())
    end)

    it("frontlightIntensityHW unconditionally returns 0", function()
      assert.are.equal(0, powerd:frontlightIntensityHW())
    end)

    it("delegates suspend and resume notifications to device", function()
      powerd:beforeSuspend()
      assert.is_true(before_suspend_called)

      powerd:afterResume()
      assert.is_true(after_resume_called)
    end)
  end)

  describe("charging status", function()
    it("reports true when sysfs status is Charging", function()
      status_content = "Charging"
      assert.is_true(powerd:isChargingHW())
    end)

    it("reports false when sysfs status is Discharging", function()
      status_content = "Discharging"
      assert.is_false(powerd:isChargingHW())
    end)
  end)
end)
