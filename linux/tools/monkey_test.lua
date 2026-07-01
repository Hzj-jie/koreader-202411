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

  local env_vars = "EMULATE_READER_W=600 EMULATE_READER_H=800 KO_MONKEY_TEST=1"
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

local function is_modal_open(target_ip, target_port)
  local url = string.format("http://%s:%d/koreader/UIManager/_window_stack/2/x", target_ip, target_port)
  local body, code = http.request(url)
  return code == 200
end

local function is_input_dialog_open(target_ip, target_port)
  local url = string.format("http://%s:%d/koreader/UIManager/_window_stack/2/widget/_input_widget/bordersize", target_ip, target_port)
  local body, code = http.request(url)
  return code == 200
end

local state = {
  menu_cooldown = 0,
  modal_open_ticks = 0,
  input_chars_typed = 0,
}

local function get_next_action(target_ip, target_port)
  local modal_open = is_modal_open(target_ip, target_port)
  local input_dialog_open = is_input_dialog_open(target_ip, target_port)

  if not input_dialog_open then
    state.input_chars_typed = 0
  end

  if modal_open then
    state.modal_open_ticks = state.modal_open_ticks + 1
  else
    state.modal_open_ticks = 0
  end

  -- If a modal has been open for too long (e.g. 5 ticks), force dismiss it
  if state.modal_open_ticks > 8 then
    print("[*] Modal stuck detected! Sending Escape to dismiss...")
    state.modal_open_ticks = 0
    return { type = "key", value = "Esc" }
  end

  -- If it is an input dialog, type some characters first, then enter
  if input_dialog_open then
    if state.input_chars_typed < 4 then
      local charset = {"t", "e", "s", "t", "m", "o", "n", "k", "y"}
      local char = charset[math.random(1, #charset)]
      state.input_chars_typed = state.input_chars_typed + 1
      return { type = "key", value = char }
    else
      state.input_chars_typed = 0
      return { type = "key", value = "Enter" }
    end
  end

  local rand = math.random()

  -- If modal is open (but not an input dialog), focus on keys (like Enter, Esc, Up, Down) to navigate it
  if modal_open then
    if rand < 0.40 then
      -- Tap inside modal bounds (usually center of the screen)
      local x = math.random(150, 450)
      local y = math.random(300, 500)
      return { type = "touch", x = x, y = y }
    elseif rand < 0.70 then
      -- Navigate Up/Down
      local key = math.random() < 0.5 and "Down" or "Up"
      return { type = "key", value = key }
    else
      -- Confirm/Dismiss
      local key = math.random() < 0.6 and "Enter" or "Esc"
      return { type = "key", value = key }
    end
  end

  -- Normal mode (no modal open)
  if state.menu_cooldown > 0 then
    state.menu_cooldown = state.menu_cooldown - 1
  end

  if rand < 0.65 then
    -- 65% probability: Page turning (reading)
    if math.random() < 0.85 then
      -- Turn forward (Right zone)
      local x = math.random(450, 590)
      local y = math.random(200, 600)
      return { type = "touch", x = x, y = y }
    else
      -- Turn backward (Left zone)
      local x = math.random(10, 150)
      local y = math.random(200, 600)
      return { type = "touch", x = x, y = y }
    end
  elseif rand < 0.80 then
    -- 15% probability: Keyboard navigation
    local keys = {"Right", "Left", "Down", "Up"}
    local keyname = keys[math.random(1, #keys)]
    return { type = "key", value = keyname }
  elseif rand < 0.90 then
    -- 10% probability: Content area taps
    local x = math.random(150, 450)
    local y = math.random(200, 600)
    return { type = "touch", x = x, y = y }
  else
    -- 10% probability: Toggle Menu (Top or Bottom zones)
    if state.menu_cooldown == 0 then
      state.menu_cooldown = 10 -- do not toggle menu again for next 10 actions
      local top = math.random() < 0.7
      if top then
        -- Top bar menu
        local x = math.random(50, 550)
        local y = math.random(10, 80)
        return { type = "touch", x = x, y = y }
      else
        -- Bottom bar menu
        local x = math.random(50, 550)
        local y = math.random(720, 780)
        return { type = "touch", x = x, y = y }
      end
    else
      -- Cooldown active, fallback to page turn forward
      local x = math.random(450, 590)
      local y = math.random(200, 600)
      return { type = "touch", x = x, y = y }
    end
  end
end

print(string.format("[+] Connected! Injecting %d guided monkey events...", count))
math.randomseed(os.time())

local passed = true
local action_err = nil

for i = 1, count do
  local action = get_next_action(ip, port)
  local url
  if action.type == "touch" then
    url = string.format("http://%s:%d/koreader/touch/%d/%d", ip, port, action.x, action.y)
  else
    url = string.format("http://%s:%d/koreader/key/%s", ip, port, action.value)
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
