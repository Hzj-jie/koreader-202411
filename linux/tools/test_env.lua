local socket = require("socket")
local test_env = {}

function test_env.free_ports()
  os.execute("fuser -k -n tcp 8088 2>/dev/null")
  os.execute("fuser -k -n tcp 8089 2>/dev/null")
  socket.select(nil, nil, 0.5)
end

function test_env.detect_headless()
  local is_ssh = (os.getenv("SSH_CLIENT") ~= nil)
    or (os.getenv("SSH_TTY") ~= nil)
    or (os.getenv("SSH_CONNECTION") ~= nil)

  local has_screen = false
  if os.getenv("DISPLAY") and not is_ssh then
    local ok = os.execute("xset -q >/dev/null 2>&1")
    if ok == 0 or ok == true then
      has_screen = true
    end
  end

  return not has_screen
end

function test_env.parse_args(args)
  local parsed = {
    headless = test_env.detect_headless(),
    ip = nil,
    port = nil,
    count = 100,
  }

  local idx = 1
  while idx <= #args do
    local arg = args[idx]
    if arg == "--headless" then
      parsed.headless = true
      idx = idx + 1
    elseif arg == "--headful" then
      parsed.headless = false
      idx = idx + 1
    elseif arg == "--ip" and args[idx+1] then
      parsed.ip = args[idx+1]
      idx = idx + 2
    elseif arg == "--port" and args[idx+1] then
      parsed.port = tonumber(args[idx+1])
      idx = idx + 2
    elseif (arg == "-n" or arg == "--n") and args[idx+1] then
      parsed.count = tonumber(args[idx+1])
      idx = idx + 2
    elseif arg == "--ssh-target" and args[idx+1] then
      parsed.ssh_target = args[idx+1]
      idx = idx + 2
    elseif arg == "--device-dir" and args[idx+1] then
      parsed.device_dir = args[idx+1]
      idx = idx + 2
    else
      idx = idx + 1
    end
  end

  local env_headful = os.getenv("HEADFUL")
  local env_headless = os.getenv("HEADLESS")
  if env_headful == "1" or env_headful == "true" then
    parsed.headless = false
  elseif env_headless == "1" or env_headless == "true" then
    parsed.headless = true
  end

  return parsed
end

return test_env
