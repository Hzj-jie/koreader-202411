-- Portable Lua Monkey Test Runner for KOReader
require("setupkoenv")
package.path = "tools/?.lua;" .. package.path
local test_env = require("test_env")
local socket = require("socket")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")

-- Sleep helper using socket.select
local function sleep(sec)
  socket.select(nil, nil, sec)
end

local function setup_environment(config_dir, port)
  os.execute("mkdir -p " .. config_dir .. "/koreader")
  local settings_path = config_dir .. "/koreader/settings.reader.lua"
  local f = io.open(settings_path, "w")
  if f then
    f:write(string.format([[
return {
  ["color_rendering"] = true,
  ["debug"] = true,
  ["debug_verbose"] = true,
  ["httpinspector_autostart"] = true,
  ["httpinspector_port"] = %d,
  ["quickstart_shown_version"] = 2999010100,
  ["plugins_disabled"] = {
    ["autowarmth"] = true,
    ["calibre"] = true,
    ["japanese"] = true,
    ["movetoarchive"] = true,
    ["profiles"] = true,
    ["wallabag"] = true,
    ["statistics"] = true,
  }
}
]], port))
    f:close()
    print("[*] Environment configured at " .. settings_path)
  else
    error("Failed to write settings file: " .. settings_path)
  end
end

local function run_monkey_test()
  local has_screen = test_env.detect_visual_output()

  local actions = 100
  local visual = has_screen
  local ip_address = nil
  local port = nil

  local arg_idx = 1
  while arg_idx <= #arg do
    if arg[arg_idx] == "-n" then
      actions = tonumber(arg[arg_idx+1]) or 100
      arg_idx = arg_idx + 2
    elseif arg[arg_idx] == "--visual" or arg[arg_idx] == "--headful" or arg[arg_idx] == "-v" then
      visual = true
      arg_idx = arg_idx + 1
    elseif arg[arg_idx] == "--headless" then
      visual = false
      arg_idx = arg_idx + 1
    elseif arg[arg_idx] == "--ip" and arg[arg_idx+1] then
      ip_address = arg[arg_idx+1]
      arg_idx = arg_idx + 2
    elseif arg[arg_idx] == "--port" and arg[arg_idx+1] then
      port = tonumber(arg[arg_idx+1])
      arg_idx = arg_idx + 2
    else
      arg_idx = arg_idx + 1
    end
  end

  local is_real_device = (ip_address ~= nil)
  port = port or (is_real_device and 8080 or 8088)
  local base_url
  if is_real_device then
    base_url = string.format("http://%s:%d/koreader", ip_address, port)
    print(string.format("[*] Target Mode: Remote Real Device (%s:%d)", ip_address, port))
  else
    base_url = string.format("http://localhost:%d/koreader", port)
    print(string.format("[*] Target Mode: Local Emulator (localhost:%d)", port))
  end

  if not is_real_device then
    local config_dir = "/tmp/koreader_monkey_test"

    -- Reset existing environment
    os.execute("rm -rf " .. config_dir)
    setup_environment(config_dir, port)

    local mode_desc = visual and "visual" or "headless"
    print(string.format("[*] Starting KOReader under emulator (%s) with httpinspector...", mode_desc))

    -- Run KOReader in background
    -- We set KO_MULTIUSER=1 and XDG_CONFIG_HOME
    local sdl_driver_env = "SDL_VIDEODRIVER=dummy"
    if visual then
      sdl_driver_env = ""
    end

    local cmd = string.format(
      "%s KO_MULTIUSER=1 XDG_CONFIG_HOME=%s ./luajit reader.lua -d > /tmp/koreader_stdout.log 2>&1 &",
      sdl_driver_env,
      config_dir
    )

    -- Resolve path to linux/ directory from the script location
    -- In lua, arg[0] is the script path
    local script_dir = arg[0]:match("(.+)/[^/]+$") or "."

    -- We change dir to linux/ to run reader.lua
    local run_cmd = string.format("cd %s/.. && %s", script_dir, cmd)
    os.execute(run_cmd)
  end

  -- Wait for HTTP server to become responsive
  local server_ready = false
  print("Waiting for KOReader HTTP server to start...")
  for i = 1, 25 do
    local body, code = http.request(base_url .. "/")
    if code == 200 then
      server_ready = true
      break
    end
    sleep(0.2)
  end

  if not server_ready then
    print("[!] Error: KOReader HTTP server did not start.")
    os.execute("pkill -f 'luajit reader.lua'")
    os.exit(1)
  end

  print("[*] Connection successful! Starting random HTTP input injection...")

  local width = 600
  local height = 800

  -- Initialize math.random seed
  math.randomseed(os.time())

  local keys = { 13, 27, 1073741905, 1073741906 }

  for i = 1, actions do
    if not is_real_device then
      -- Check if process is still alive (e.g. using pgrep)
      local p = io.popen("pgrep -f 'luajit reader.lua'")
      local pid = p:read("*all")
      p:close()
      if pid == "" then
        print("[!] Crash detected at action " .. i)
        os.exit(1)
      end
    end

    local action_type = ({ "tap", "swipe", "key" })[math.random(1, 3)]
    local url
    if action_type == "tap" then
      local x = math.random(10, width - 10)
      local y = math.random(10, height - 10)
      url = string.format("%s/touch/tap/%d/%d", base_url, x, y)
    elseif action_type == "swipe" then
      local x1 = math.random(10, width - 10)
      local y1 = math.random(10, height - 10)
      local x2 = math.random(10, width - 10)
      local y2 = math.random(10, height - 10)
      url = string.format("%s/touch/swipe/%d/%d/%d/%d/10", base_url, x1, y1, x2, y2)
    else
      local key = keys[math.random(1, #keys)]
      url = string.format("%s/key/%d", base_url, key)
    end

    -- Send request
    local body, code = http.request(url)
    if not code or code ~= 200 then
      print(string.format("[!] HTTP request failed at action %d: %s", i, tostring(code)))
    end

    sleep(0.2)
  end

  print("[*] Terminating KOReader process cleanly...")
  -- Request Quit cleanly
  http.request(base_url .. "/event/Quit")
  sleep(1.0)

  if not is_real_device then
    -- Ensure it's terminated locally
    os.execute("pkill -f 'luajit reader.lua'")

    -- Read the stdout log to verify no uncaught crashes/tracebacks
    local lf = io.open("/tmp/koreader_stdout.log", "r")
    if lf then
      local content = lf:read("*all")
      lf:close()

      local is_crash = false
      if content:find("coroutine crashed:") or content:find("luajit:") or content:find("./luajit:") then
        is_crash = true
      end

      if is_crash then
        print("[!] Uncaught LuaJIT error/crash detected in log output!")
        print("====== KOReader Stdout output ======")
        print(content)
        os.exit(1)
      end
    end
  end

  print(string.format("[+] Monkey test PASSED. Successfully ran %d random actions with no crashes.", actions))
  os.exit(0)
end

run_monkey_test()
