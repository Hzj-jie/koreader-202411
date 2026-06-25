package.path = "tools/?.lua;?.lua;" .. package.path
require("setupkoenv")
local socket = require("socket")
local http = require("socket.http")
local test_env = require("test_env")

local config = test_env.parse_args(arg)
local ip = config.ip or "127.0.0.1"
local port = config.port or 8088
local count = config.count
local headless = config.headless

local spawned_pid = nil

-- Check if we need to start a local emulator
if ip == "127.0.0.1" or ip == "localhost" then
  -- Clean up any old httpinspector.port files
  os.remove("httpinspector.port")

  print(string.format("[*] Starting local emulator (%s)...", headless and "headless" or "headful"))
  
  -- Setup settings.reader.lua to use port 0 (auto-assign) and autostart
  local luasettings = require("luasettings")
  local settings = luasettings:open("settings.reader.lua")
  settings:save("httpinspector_port", 0)
  settings:save("httpinspector_autostart", true)
  settings:flush()

  local env_vars = "EMULATE_READER_W=600 EMULATE_READER_H=800"
  if headless then
    env_vars = env_vars .. " SDL_VIDEODRIVER=dummy"
  end
  
  -- Start KOReader from the parent directory
  local cmd = string.format("%s ./luajit reader.lua -d > /tmp/koreader_emu_monkey.log 2>&1 & echo $!", env_vars)
  local pipe = io.popen(cmd)
  spawned_pid = tonumber(pipe:read("*line"))
  pipe:close()
  
  if not spawned_pid then
    error("Failed to start emulator subprocess.")
  end

  -- Wait for httpinspector.port to be created and read it
  print("[*] Waiting for httpinspector to bind a port...")
  for i = 1, 50 do
    socket.select(nil, nil, 0.2) -- sleep 200ms
    local f = io.open("httpinspector.port", "r")
    if f then
      local val = f:read("*line")
      f:close()
      if val then
        port = tonumber(val)
        break
      end
    end
  end

  if not port or port == 0 then
    os.execute(string.format("kill -9 %d 2>/dev/null", spawned_pid))
    error("Emulator started but httpinspector did not write a valid port within 10 seconds.")
  end
  print(string.format("[*] httpinspector started on dynamic port: %d", port))
end

print(string.format("[+] Connected! Injecting %d random events...", count))
math.randomseed(os.time())

local passed = true
local action_err = nil

for i = 1, count do
  local url
  if math.random() < 0.90 then
    local x = math.random(10, 590)
    local y = math.random(10, 790)
    url = string.format("http://%s:%d/koreader/touch/%d/%d", ip, port, x, y)
  else
    local keys = {"Right", "Left", "Down", "Up"}
    local keyname = keys[math.random(1, #keys)]
    url = string.format("http://%s:%d/koreader/key/%s", ip, port, keyname)
  end

  local body, code = http.request(url)
  if code ~= 200 then
    passed = false
    action_err = string.format("HTTP request failed with code %s (url: %s)", tostring(code), url)
    break
  end

  socket.select(nil, nil, math.random(5, 15) / 100)
end

if spawned_pid then
  print(string.format("[*] Cleaning up local emulator (PID: %d)...", spawned_pid))
  os.execute(string.format("kill %d 2>/dev/null", spawned_pid))
  -- Wait a moment for process to die
  socket.select(nil, nil, 0.5)
  os.execute(string.format("kill -9 %d 2>/dev/null", spawned_pid))
end

if passed then
  print(string.format("[+] Successfully completed all %d monkey test actions.", count))
else
  error("[-] Monkey test failed during action injection: " .. tostring(action_err))
end
