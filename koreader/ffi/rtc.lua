--[[--
Module for interfacing with the RTC (real time clock).

See <http://man7.org/linux/man-pages/man4/rtc.4.html> for technical details.

@module ffi.rtc
]]

local ffi = require("ffi")
local bor = bit.bor
local C = ffi.C

-- Load header definitions for functions and constants to the ffi.C namespace.
require("ffi/posix_h")
require("ffi/rtc_h")

-----------------------------------------------------------------

local RTC = {
  dev_rtc = "/dev/rtc0",
}

-- Helpers for HCToSys
local function set_kernel_tz(tz)
  local re = C.settimeofday(nil, tz)
  if re == -1 then
    local err = ffi.string(C.strerror(ffi.errno()))
    print("set_kernel_tz settimeofday", re, err)
    return nil, re, err
  end

  return true
end

--[[--
Sets the system clock based on the hardware clock.

(e.g., hwclock --hctosys).
Heavily inspired by busybox's hwclock applet.
--]]
function RTC:HCToSys()
  local ok, err, re
  local fd = C.open(self.dev_rtc, bor(C.O_RDONLY, C.O_NONBLOCK, C.O_CLOEXEC))
  if fd == -1 then
    err = ffi.string(C.strerror(ffi.errno()))
    print("HCToSys open " .. self.dev_rtc, fd, err)
    return nil, fd, err
  end

  -- Read the hardware clock
  local tm = ffi.new("struct tm") -- tm is a superset of rtc_time, so we're good.
  re = C.ioctl(fd, C.RTC_RD_TIME, tm)
  if re == -1 then
    err = ffi.string(C.strerror(ffi.errno()))
    print("HCToSys ioctl RTC_RD_TIME", re, err)
    return nil, re, err
  end
  re = C.close(fd)
  if re == -1 then
    err = ffi.string(C.strerror(ffi.errno()))
    print("HCToSys close " .. self.dev_rtc, re, err)
    return nil, re, err
  end

  -- Convert that UTC broken down representation to an UTC time_t...
  local t = C.timegm(tm)

  -- We want a timeval for settimeofday
  local tv = ffi.new("struct timeval")
  tv.tv_sec = t

  -- Deal with some more kernel & TZ nonsense...
  -- 1. Lock the kernel's warp_clock function
  --    (iff that's the first settimeofday call after a cold boot! i.e., in our case, that's mostly going to be a NOP).
  -- 2. Set the kernel timezone.
  -- c.f., comments in hwclock in both busybox & util-linux, as well as gettimeofday(2) for more details.
  local tz = ffi.new("struct timezone")
  ok, re, err = set_kernel_tz(tz)
  if not ok then
    return nil, re, err
  end
  local cur = ffi.new("time_t[1]")
  cur[0] = C.time(nil)
  local broken = C.localtime(cur)
  tz.tz_minuteswest = -broken.tm_gmtoff / 60
  ok, re, err = set_kernel_tz(tz)
  if not ok then
    return nil, re, err
  end

  -- Finally set the system clock
  re = C.settimeofday(tv, nil)
  if re == -1 then
    err = ffi.string(C.strerror(ffi.errno()))
    print("HCToSys settimeofday", re, err)
    return nil, re, err
  end

  return true
end

return RTC
