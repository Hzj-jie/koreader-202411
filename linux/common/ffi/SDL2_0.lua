-- Consolidated TCP input-injection wrapper for SDL2_0
local ffi = require("ffi")
local socket = require("socket")

-- Read the real SDL2_0.lua from koreader/ffi/SDL2_0.lua (via frontend/ symlink)
local file = io.open("frontend/ffi/SDL2_0.lua", "r")
if not file then
  file = io.open("../koreader/ffi/SDL2_0.lua", "r")
end
if not file then
  error("Could not locate original koreader/ffi/SDL2_0.lua")
end
local content = file:read("*all")
file:close()

-- Load the real SDL2 module
local real_SDL = assert(loadstring(content))()

-- Simulated Input Queue
local inputQueue = {}
local C = ffi.C

local function genEmuEvent(evtype, code, value)
  local timespec = ffi.new("struct timespec")
  C.clock_gettime(C.CLOCK_REALTIME, timespec)
  local timev = {
    sec = tonumber(timespec.tv_sec),
    usec = math.floor(tonumber(timespec.tv_nsec / 1000)),
  }
  local ev = {
    type = tonumber(evtype),
    code = tonumber(code),
    value = tonumber(value) or value,
    time = timev,
  }
  table.insert(inputQueue, ev)
end

-- Bind TCP socket on localhost:8088
local server = assert(socket.bind("127.0.0.1", 8088))
server:settimeout(0)

local client = nil

local function pollSocket()
  if not client then
    client = server:accept()
    if client then
      client:settimeout(0)
    end
  end
  if client then
    local line, err = client:receive()
    if not err then
      local cmd, arg1, arg2 = line:match("^(%a+)%s*(%d*)%s*(%d*)$")
      if cmd == "touch" then
        local x = tonumber(arg1)
        local y = tonumber(arg2)
        -- Touch down
        genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, 0)
        genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, 1)
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, x)
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, y)
        genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
        -- Touch up
        genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, 0)
        genEmuEvent(C.EV_ABS, C.ABS_MT_TRACKING_ID, -1)
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, x)
        genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_Y, y)
        genEmuEvent(C.EV_SYN, C.SYN_REPORT, 0)
      elseif cmd == "key" then
        local code = tonumber(arg1)
        genEmuEvent(C.EV_KEY, code, 1)
        genEmuEvent(C.EV_KEY, code, 0)
      end
      client:send("OK\n")
    elseif err == "closed" then
      client = nil
    end
  end
end

-- Override waitForEvent
local original_waitForEvent = real_SDL.waitForEvent
function real_SDL.waitForEvent(sec, usec)
  pollSocket()
  if #inputQueue > 0 then
    local events = inputQueue
    inputQueue = {}
    return true, events
  end

  -- Clamp timeout to 50ms to ensure regular socket polling
  local poll_sec = 0
  local poll_usec = 50000
  if sec and (sec < poll_sec or (sec == poll_sec and usec < poll_usec)) then
    poll_sec = sec
    poll_usec = usec
  end

  local ok, err = original_waitForEvent(poll_sec, poll_usec)
  if ok then
    return ok, err
  end

  pollSocket()
  if #inputQueue > 0 then
    local events = inputQueue
    inputQueue = {}
    return true, events
  end

  return ok, err
end

return real_SDL
