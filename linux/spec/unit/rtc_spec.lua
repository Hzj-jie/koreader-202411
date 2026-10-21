local ffi
local RTC

describe("RTC module", function()
  local last_ioctl_cmd
  local last_wkalrm
  local original_ffi

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    original_ffi = ffi
    local original_C = ffi.C

    local mock_C = setmetatable({
      open = function(_path, _flags)
        return 42
      end,
      close = function(_fd)
        return 0
      end,
      ioctl = function(_fd, cmd, arg)
        last_ioctl_cmd = tonumber(cmd)
        if cmd == original_C.RTC_WKALM_SET and arg ~= nil then
          last_wkalrm = ffi.new("struct rtc_wkalrm")
          ffi.copy(last_wkalrm, arg, ffi.sizeof("struct rtc_wkalrm"))
        end
        return 0
      end,
    }, {
      __index = original_C,
    })

    local mock_ffi = setmetatable({
      C = mock_C,
    }, {
      __index = ffi,
    })

    package.loaded["ffi"] = mock_ffi
    package.loaded["ffi/rtc"] = nil
    RTC = require("ffi/rtc")
  end)

  teardown(function()
    package.loaded["ffi"] = original_ffi
    package.loaded["ffi/rtc"] = nil
  end)

  before_each(function()
    last_ioctl_cmd = nil
    last_wkalrm = nil
  end)

  it("should convert seconds from now to epoch", function()
    local epoch = RTC:secondsFromNowToEpoch(60)
    assert.is_number(epoch)
    assert.is_true(epoch >= os.time() + 59)
  end)

  it(
    "should pass RTC_AIE_OFF to ioctl when disabling alarm interrupt",
    function()
      RTC:toggleAlarmInterrupt(false)
      assert.are.equal(ffi.C.RTC_AIE_OFF, last_ioctl_cmd)
    end
  )

  it(
    "should set enabled to 0 in rtc_wkalrm when disabling wakeup alarm",
    function()
      RTC:setWakeupAlarm(os.time() + 300, false)
      assert.is_not_nil(last_wkalrm)
      assert.are.equal(0, last_wkalrm.enabled)
    end
  )
end)
