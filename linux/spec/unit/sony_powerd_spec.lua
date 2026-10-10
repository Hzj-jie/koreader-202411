-- luacheck: ignore 122
local SonyPRSTUX_PowerD

describe("device/sony-prstux/powerd module", function()
  setup(function()
    require("commonrequire")
    SonyPRSTUX_PowerD = require("device/sony-prstux/powerd")
  end)

  it("reads capacity and charging status from hardware sysfs files", function()
    local inst = SonyPRSTUX_PowerD:new({
      read_int_file = function(self, path)
        if path:match("capacity$") then
          return 85
        end
      end,
      read_str_file = function(self, path)
        if path:match("status$") then
          return "Charging"
        end
      end,
    })

    assert.are.equal(85, inst:getCapacityHW())
    assert.is_true(inst:isChargingHW())
  end)

  it(
    "returns 0 when no frontlight is present, and valid intensity when enabled",
    function()
      local inst = SonyPRSTUX_PowerD:new({
        device = {
          hasFrontlight = function()
            return false
          end,
          hasNaturalLight = function()
            return false
          end,
        },
      })

      assert.are.equal(0, inst:frontlightIntensityHW())

      -- When frontlight is present, frontlightIntensityHW should return a numeric intensity.
      -- In production lines 16-20:
      --   function SonyPRSTUX_PowerD:frontlightIntensityHW()
      --     if not self.device:hasFrontlight() then
      --       return 0
      --     end
      --   end
      -- It is missing a return statement when hasFrontlight() is true, returning nil.
      inst.device.hasFrontlight = function()
        return true
      end
      assert.is_number(inst:frontlightIntensityHW())
    end
  )
end)
