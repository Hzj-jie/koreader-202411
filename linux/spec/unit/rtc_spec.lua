local ffi
local RTC

describe("RTC module", function()
  local original_ffi
  local mock_open_fd
  local mock_ioctl_ret
  local mock_tm
  local recorded_ioctl_cmd
  local recorded_tv_sec
  local settimeofday_calls

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    original_ffi = ffi
    local original_C = ffi.C

    local mock_C = setmetatable({
      open = function(_path, _flags)
        return mock_open_fd
      end,
      close = function(_fd)
        return 0
      end,
      ioctl = function(_fd, cmd, arg)
        recorded_ioctl_cmd = tonumber(cmd)
        if cmd == original_C.RTC_RD_TIME and arg ~= nil and mock_tm ~= nil then
          ffi.copy(arg, mock_tm, ffi.sizeof("struct tm"))
        end
        return mock_ioctl_ret
      end,
      settimeofday = function(tv, _tz)
        settimeofday_calls = settimeofday_calls + 1
        if tv ~= nil then
          recorded_tv_sec = tonumber(tv.tv_sec)
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
    mock_open_fd = 42
    mock_ioctl_ret = 0
    mock_tm = ffi.new("struct tm")
    recorded_ioctl_cmd = nil
    recorded_tv_sec = nil
    settimeofday_calls = 0
  end)

  it(
    "reads hardware clock via RTC_RD_TIME and sets system clock in HCToSys",
    function()
      -- 2024-01-15 12:30:45 UTC
      mock_tm.tm_year = 124
      mock_tm.tm_mon = 0
      mock_tm.tm_mday = 15
      mock_tm.tm_hour = 12
      mock_tm.tm_min = 30
      mock_tm.tm_sec = 45

      local ok = RTC:HCToSys()
      assert.is_true(ok)
      assert.are.equal(tonumber(ffi.C.RTC_RD_TIME), recorded_ioctl_cmd)
      assert.are.equal(3, settimeofday_calls)
      assert.are.equal(1705321845, recorded_tv_sec)
    end
  )

  it("returns nil and error code when RTC device open fails", function()
    mock_open_fd = -1
    local ok, code = RTC:HCToSys()
    assert.is_nil(ok)
    assert.are.equal(-1, code)
  end)
end)
