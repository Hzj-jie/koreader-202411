package.path = "?.lua;" .. package.path
require("setupkoenv")
local socket = require("socket")

local ip = "127.0.0.1"
local port = 8088
local count = 100

-- Parse command line arguments
local idx = 1
while idx <= #arg do
  if arg[idx] == "-ip" then
    ip = arg[idx+1]
    idx = idx + 2
  elseif arg[idx] == "-port" then
    port = tonumber(arg[idx+1])
    idx = idx + 2
  elseif arg[idx] == "-n" then
    count = tonumber(arg[idx+1])
    idx = idx + 2
  else
    idx = idx + 1
  end
end

print(string.format("[*] Connecting to event injection server at %s:%d...", ip, port))
local conn, err = socket.connect(ip, port)
if not conn then
  error(string.format("Could not connect to %s:%d: %s", ip, port, tostring(err)))
end

print(string.format("[+] Connected! Injecting %d random events...", count))
math.randomseed(os.time())

for i = 1, count do
  local cmd
  if math.random() < 0.90 then
    local x = math.random(10, 590)
    local y = math.random(10, 790)
    cmd = string.format("touch %d %d\n", x, y)
  else
    local keys = {1073741903, 1073741904, 1073741905, 1073741906}
    local code = keys[math.random(1, #keys)]
    cmd = string.format("key %d\n", code)
  end

  conn:send(cmd)
  local response, err = conn:receive()
  if err or response ~= "OK" then
    error(string.format("[-] Connection lost or invalid response at action %d: %s", i, tostring(err or response)))
  end

  -- Throttle speed slightly (50ms - 150ms delay)
  socket.select(nil, nil, math.random(5, 15) / 100)
end

conn:close()
print(string.format("[+] Successfully completed all %d monkey test actions.", count))
