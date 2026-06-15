-- bit.lua compatibility for Lua 5.3+ using native operators
local bit = {}

bit.tobit = load([[
  return function(x)
    local r = x & 0xffffffff
    if r >= 0x80000000 then
      return r - 0x100000000
    else
      return r
    end
  end
]])()

local tobit = bit.tobit

bit.lshift = load([[
  local tobit = ...
  return function(x, y)
    return tobit(x << (y & 31))
  end
]])(tobit)

bit.rshift = load([[
  local tobit = ...
  return function(x, y)
    return tobit((x & 0xffffffff) >> (y & 31))
  end
]])(tobit)

bit.arshift = load([[
  local tobit = ...
  return function(x, y)
    local shift = y & 31
    local r = (x & 0xffffffff) >> shift
    if (x & 0x80000000) ~= 0 and shift > 0 then
      local mask32 = (0xffffffff >> shift)
      r = r | ~mask32 & 0xffffffff
    end
    return tobit(r)
  end
]])(tobit)

bit.band = load([[
  local tobit = ...
  return function(x, y)
    return tobit(x & y)
  end
]])(tobit)

bit.bor = load([[
  local tobit = ...
  return function(x, y)
    return tobit(x | y)
  end
]])(tobit)

bit.bxor = load([[
  local tobit = ...
  return function(x, y)
    return tobit(x ~ y)
  end
]])(tobit)

bit.bnot = load([[
  local tobit = ...
  return function(x)
    return tobit(~x)
  end
]])(tobit)

bit.bswap = load([[
  local tobit = ...
  return function(x)
    local r = ((x & 0xff) << 24) |
              ((x & 0xff00) << 8) |
              ((x & 0xff0000) >> 8) |
              ((x & 0xff000000) >> 24)
    return tobit(r)
  end
]])(tobit)

bit.tohex = load([[
  return function(x, n)
    n = n or 8
    local mask
    if n < 0 then
      n = -n
      mask = (1 << (4 * n)) - 1
      return string.format("%0" .. n .. "X", x & mask)
    else
      mask = (1 << (4 * n)) - 1
      return string.format("%0" .. n .. "x", x & mask)
    end
  end
]])()

return bit
