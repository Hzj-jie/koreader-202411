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
end)
