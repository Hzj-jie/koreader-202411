#!/usr/bin/env ./luajit
-- Comparative pagination benchmark runner

require("setupkoenv")

local ffiUtil = require("ffi/util")
local http = require("socket.http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")

local function url_encode(str)
  if not str then return nil end
  -- Strict percent-encoding without CRLF normalization for newlines
  str = str:gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return str
end

local BENCHMARK_HOME = "/tmp/koreader_benchmark"
local IP_ADDRESS
local PORT
local BASE_URL
local SSH_TARGET
local DEVICE_DIR = "/tmp"
local IS_REAL_DEVICE
local IS_LOCAL_IP
local pwd = lfs.currentdir()
local is_baseline = pwd:find("origin.linux") ~= nil
local EMULATOR_LOG_PATH = is_baseline
    and "/tmp/benchmark_koreader_emulator_baseline.log"
  or "/tmp/benchmark_koreader_emulator_master.log"
-- Multi-document target configurations (portable reflowable formats only)
local TARGET_DOCUMENTS = {
  "test/juliet.epub",
  "test/leaves.epub",
  "test/sample.pdf",
  "test/sample.txt",
}
-- SSH session context detection to prevent remote high-latency GUI rendering delays
local is_ssh = (os.getenv("SSH_CLIENT") ~= nil)
  or (os.getenv("SSH_TTY") ~= nil)
  or (os.getenv("SSH_CONNECTION") ~= nil)

-- Reachable active X11 display screen query auto-detection
local has_screen = false
if os.getenv("DISPLAY") and not is_ssh then
  local ok = os.execute("xset -q >/dev/null 2>&1")
  if ok == 0 or ok == true then
    has_screen = true
  end
end

-- Resolve baseline viewport execution mode (Headless vs. Headful)
local HEADFUL = has_screen

do
  -- CLI flag overrides
  local i = 1
  while i <= #arg do
    if arg[i] == "--headful" then
      HEADFUL = true
      i = i + 1
    elseif arg[i] == "--headless" then
      HEADFUL = false
      i = i + 1
    elseif arg[i] == "--ip" and arg[i+1] then
      IP_ADDRESS = arg[i+1]
      i = i + 2
    elseif arg[i] == "--port" and arg[i+1] then
      PORT = tonumber(arg[i+1])
      i = i + 2
    elseif arg[i] == "--ssh-target" and arg[i+1] then
      SSH_TARGET = arg[i+1]
      i = i + 2
    elseif arg[i] == "--device-dir" and arg[i+1] then
      DEVICE_DIR = arg[i+1]
      i = i + 2
    else
      i = i + 1
    end
  end

  -- Environment variable overrides
  local env_headful = os.getenv("HEADFUL")
  local env_headless = os.getenv("HEADLESS")
  if env_headful == "1" or env_headful == "true" then
    HEADFUL = true
  elseif env_headless == "1" or env_headless == "true" then
    HEADFUL = false
  end

  -- Resolve final configuration based on execution mode
  if IP_ADDRESS then
    IS_REAL_DEVICE = true
    PORT = PORT or 8080 -- default HTTP port for real devices
    SSH_TARGET = SSH_TARGET or string.format("root@%s", IP_ADDRESS)
    BASE_URL = string.format("http://%s:%d/koreader", IP_ADDRESS, PORT)

    -- Detect if target IP is local to bypass network-overhead SSH/SCP operations
    if IP_ADDRESS == "localhost" or IP_ADDRESS == "127.0.0.1" then
      IS_LOCAL_IP = true
    else
      local p = io.popen("hostname -I")
      if p then
        local host_ips = p:read("*all")
        p:close()
        local padded_ips = " " .. host_ips:gsub("\r?\n", " ") .. " "
        if padded_ips:find("%s" .. IP_ADDRESS:gsub("%.", "%%.") .. "%s") then
          IS_LOCAL_IP = true
        end
      end
    end

    if IS_LOCAL_IP then
      print(string.format("[*] Target Mode: Local Real Device (%s:%d) [Bypassing SSH/SCP with direct local filesystem cp/rm]", IP_ADDRESS, PORT))
    else
      print(string.format("[*] Target Mode: Remote Real Device (%s:%d)", IP_ADDRESS, PORT))
      print(string.format("[*] SSH Target: %s", SSH_TARGET))
    end
    print(string.format("[*] Remote Directory: %s", DEVICE_DIR))
  else
    IS_REAL_DEVICE = false
    IS_LOCAL_IP = false
    PORT = PORT or 8088 -- default HTTP port for emulator
    BASE_URL = string.format("http://localhost:%d/koreader", PORT)
    print(string.format("[*] Target Mode: Local Emulator (localhost:%d)", PORT))
  end
end

-- Recursive mkdir (only supports absolute paths)
local function mkdir_p(path)
  local current = ""
  for dir in path:gmatch("[^/]+") do
    current = current .. "/" .. dir
    if lfs.attributes(current, "mode") ~= "directory" then
      local ok, err = lfs.mkdir(current)
      if not ok then
        error(string.format("Failed to create directory %s: %s", current, err))
      end
    end
  end
end

local function setup_environment()
  print(
    string.format("Setting up sandbox environment in %s...", BENCHMARK_HOME)
  )
  local config_dir = BENCHMARK_HOME .. "/.config/koreader"
  mkdir_p(config_dir)

  -- Write defaults.custom.lua to dynamically enforce absolute rendering settings consistency (font size 16)
  local custom_defaults_path = config_dir .. "/defaults.custom.lua"
  local df = io.open(custom_defaults_path, "w")
  if not df then
    error(
      "Failed to open custom defaults file for writing: "
        .. custom_defaults_path
    )
  end
  df:write([[-- consistent benchmark default settings overrides
return {
  DCREREADER_CONFIG_DEFAULT_FONT_SIZE = 16,
}
]])
  df:close()

  -- Write settings.reader.lua to enable httpinspector and auto-start with verbose debug trace
  local settings_path = config_dir .. "/settings.reader.lua"
  local f = io.open(settings_path, "w")
  if not f then
    error("Failed to open settings file for writing: " .. settings_path)
  end

  local settings_content = string.format(
    [[-- benchmark configuration
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
  }
}
]],
    PORT
  )
  f:write(settings_content)
  f:close()
  print("Environment setup complete.")
end

local function http_get(url)
  local body, code = http.request(url)
  if code == 200 then
    return true, body
  end
  return false, tostring(code)
end

local function get_json_val(url)
  local success, res = http_get(url)
  if success then
    local ok, data = pcall(json.decode, res)
    if ok then
      if type(data) == "table" and #data > 0 then
        return true, data[1] -- Result of function call is a JSON array: [value]
      end
      return true, data
    else
      return false, "Failed to decode JSON: " .. tostring(data)
    end
  end
  return false, res
end

local function wait_for_ready()
  print("Waiting for KOReader HTTP server to start...")
  local start_secs, start_usecs = ffiUtil.gettime()
  local server_ready = false

  -- 1. Wait for the HTTP server index to return 200 OK (signaling server is ready)
  while true do
    local now_secs, now_usecs = ffiUtil.gettime()
    local elapsed = now_secs - start_secs + (now_usecs - start_usecs) / 1000000
    if elapsed >= 15 then
      break
    end

    local success = http_get(BASE_URL .. "/")
    if success then
      server_ready = true
      break
    end
    ffiUtil.usleep(200 * 1000) -- sleep 200ms
  end

  if not server_ready then
    error("KOReader HTTP server did not start up within 15 seconds.")
  end

  print("Server is up! Waiting for document page count to resolve...")
  local page_start_secs, page_start_usecs = ffiUtil.gettime()
  local url = BASE_URL .. "/ui/document/getPageCount/"

  -- 2. Wait up to 5 seconds for a valid, non-zero page count to resolve
  while true do
    local now_secs, now_usecs = ffiUtil.gettime()
    local elapsed = now_secs - page_start_secs + (now_usecs - page_start_usecs) / 1000000
    if elapsed >= 5 then
      break
    end

    local success, val = get_json_val(url)
    if success and type(val) == "number" and val > 0 then
      print(
        string.format(
          "Document loaded successfully! Total pages: %d",
          val
        )
      )
      return val
    end
    ffiUtil.usleep(100 * 1000) -- sleep 100ms
  end

  -- Fallback to a safe default instead of crashing if the page count cannot be resolved
  print("\nWarning: Safe page count resolution timed out. Falling back to default 10 pages.")
  return 10
end

local function is_modal_open()
  -- Query the window x coordinate property (guaranteed to be a simple non-nil number) to check presence safely without recursive serialization
  local success = http_get(BASE_URL .. "/UIManager/_window_stack/2/x")
  if success then
    -- Returned 200 OK (window entry exists!)
    return true
  end
  -- Returned 404 Not Found, indicating index 2 does not exist (only permanent base ReaderUI is active)
  return false
end

local function wait_for_modal_close()
  local poll_start = ffiUtil.gettime()
  while true do
    if not is_modal_open() then
      return true
    end
    local now = ffiUtil.gettime()
    if (now - poll_start) >= 0.5 then -- 500ms timeout
      break
    end
    ffiUtil.usleep(20 * 1000) -- Check every 20ms
  end
  return false
end

local function close_modal()
  if not is_modal_open() then
    -- No modal is open, bypassing is 100% safe
    return true
  end

  -- Probe to detect if the open modal is an InputDialog
  -- Probe bordersize of _input_widget to confirm presence safely without recursive serialization overhead
  local success_probe =
    http_get(BASE_URL .. "/UIManager/_window_stack/2/widget/_input_widget/bordersize")
  local is_input_dialog = success_probe

  if is_input_dialog then
    -- 1. Trigger "Exit" event first to close the virtual keyboard if open
    http_get(BASE_URL .. "/event/Exit")
    ffiUtil.usleep(50 * 1000)

    -- 2. Trigger "CloseDialog" to dismiss the InputDialog modal
    http_get(BASE_URL .. "/event/CloseDialog")
    if wait_for_modal_close() then
      return true
    end
  else
    -- 3. It's a DictQuickLookup modal!
    -- Trigger "Exit" event first (closes DictQuickLookup on master target immediately)
    if not is_baseline then
      http_get(BASE_URL .. "/event/Exit")
      if wait_for_modal_close() then
        return true
      end
    end

    -- Trigger baseline "Close" event (closes DictQuickLookup on baseline target)
    local success_close = http_get(BASE_URL .. "/event/Close")
    if success_close and wait_for_modal_close() then
      return true
    end

    -- Retry (after 200ms sleep to let slow db queries finalize under system load spikes)
    print(
      "\nWarning: Baseline quick-lookup close timed out, retrying event after 200ms..."
    )
    ffiUtil.usleep(200 * 1000)
    success_close = http_get(BASE_URL .. "/event/Close")
    if success_close and wait_for_modal_close() then
      return true
    end
  end

  print("\nError: Failed to close popup modal container widget!")
  return false
end

local function run_benchmark(total_pages)
  print(
    string.format(
      "\nStarting benchmark: Simulating book reading through %d pages...",
      total_pages
    )
  )

  -- Clean up any unexpected startup modals/notices first (e.g. DB migrations warning notice)
  while is_modal_open() do
    print("[*] Dismissing unexpected startup modal window...")
    local success_close = close_modal()
    if not success_close then
      print("\nError: Failed to clear startup modal from window stack!")
      break
    end
    ffiUtil.usleep(100 * 1000) -- sleep 100ms
  end

  local page_durations = {}
  local dict_durations = {}
  local keydict_durations = {}
  local keysearch_durations = {}
  local bookmark_durations = {}

  local current_page = 1
  for turn = 1, total_pages - 1 do
    local target_page = current_page + 1
    io.write(string.format("Page %d/%d: Paging...", target_page, total_pages))
    io.stdout:flush()

    local s1, u1 = ffiUtil.gettime()

    -- Send page turn event as a universal broadcast action
    local success = http_get(BASE_URL .. "/broadcast/GotoRelativePage/1")
    if not success then
      print("\nError: Failed to send page turn request!")
      break
    end

    -- Poll current page until it changes to target_page
    local success_poll = false
    local poll_start_secs, poll_start_usecs = ffiUtil.gettime()
    while true do
      local now_secs, now_usecs = ffiUtil.gettime()
      local elapsed = now_secs
        - poll_start_secs
        + (now_usecs - poll_start_usecs) / 1000000
      if elapsed >= 5 then
        break
      end

      local success_cur, val = get_json_val(BASE_URL .. "/ui/getCurrentPage/")
      if success_cur and val == target_page then
        success_poll = true
        break
      end
      ffiUtil.usleep(50 * 1000) -- Poll once per 50ms
    end

    local s2, u2 = ffiUtil.gettime()
    local duration = (s2 - s1) * 1000 + (u2 - u1) / 1000 -- in ms

    if not success_poll then
      print("\nError: Page turn timed out!")
      break
    end

    io.write(string.format(" Done (%.2f ms)", duration))
    table.insert(page_durations, duration)
    current_page = target_page

    -- 1. Simulate standard selection quick-lookup every 10 pages (except on keyboard lookup turns!)
    if target_page % 10 == 0 and target_page % 20 ~= 0 then
      io.write(" [Lookup 'Shakespeare']...")
      io.stdout:flush()
      local ds1, du1 = ffiUtil.gettime()

      -- Trigger lookup
      local success_lookup =
        http_get(BASE_URL .. "/broadcast/LookupWord/" .. url_encode('"Shakespeare"'))
      if not success_lookup then
        print("\nError: Failed to trigger dictionary lookup event!")
        break
      end

      -- Sleep 100ms to allow dictionary popup modal window to render
      ffiUtil.usleep(100 * 1000)

      -- Dismiss lookup popup modal window using stack-aware close_modal helper
      local success_close = close_modal()
      if not success_close then
        print("\nError: Failed to close dictionary popup modal window!")
        break
      end

      local ds2, du2 = ffiUtil.gettime()
      local d_duration = (ds2 - ds1) * 1000 + (du2 - du1) / 1000 -- in ms
      io.write(string.format(" Done (%.2f ms)", d_duration))
      table.insert(dict_durations, d_duration)
    end

    -- 2. Simulate keyboard dictionary search + submit + modal dismissal every 20 pages
    if target_page % 20 == 0 then
      io.write(" [Keyboard Lookup 'Shakespeare']...")
      io.stdout:flush()
      local ks1, ku1 = ffiUtil.gettime()

      -- Spawn input keyboard dialog
      local success_show = http_get(BASE_URL .. "/event/ShowDictionaryLookup")
      if not success_show then
        print("\nError: Failed to spawn dictionary lookup keyboard dialog!")
        break
      end
      ffiUtil.usleep(100 * 1000)

      if not is_modal_open() then
        print("\nError: Keyboard lookup dialog failed to map to stack!")
        break
      end

      -- Inject typing search string + confirm submit newline character ("Shakespeare\n")
      local success_type = http_get(
        BASE_URL
          .. "/UIManager/_window_stack/2/widget/_input_widget/addChars/"
          .. url_encode('"Shakespeare\n"')
      )
      if not success_type then
        print("\nError: Failed to inject typing search sequence!")
        break
      end
      ffiUtil.usleep(500 * 1000) -- Allow definitions modal popup window to load

      -- Dismiss search lookup result popup modal using stack-aware close_modal helper
      local success_close = close_modal()
      if not success_close then
        print("\nError: Failed to close keyboard lookup results modal window!")
        break
      end

      local ks2, ku2 = ffiUtil.gettime()
      local k_duration = (ks2 - ks1) * 1000 + (ku2 - ku1) / 1000 -- in ms
      io.write(string.format(" Done (%.2f ms)", k_duration))
      table.insert(keydict_durations, k_duration)
    end

    -- 2b. Simulate keyboard fulltext search input (no submit) every 24 pages
    if target_page % 24 == 0 then
      io.write(" [Keyboard Search 'Shakespeare']...")
      io.stdout:flush()
      local ks1, ku1 = ffiUtil.gettime()

      -- Spawn input keyboard dialog
      local success_show = http_get(BASE_URL .. "/event/ShowFulltextSearchInput")
      if not success_show then
        print("\nError: Failed to spawn fulltext search keyboard dialog!")
        break
      end
      ffiUtil.usleep(100 * 1000)

      if not is_modal_open() then
        print("\nError: Keyboard search dialog failed to map to stack!")
        break
      end

      -- Inject typing search string (no newline to avoid triggering actual search)
      local success_type = http_get(
        BASE_URL
          .. "/UIManager/_window_stack/2/widget/_input_widget/addChars/"
          .. url_encode('"Shakespeare"')
      )
      if not success_type then
        print("\nError: Failed to inject typing search sequence!")
        break
      end
      ffiUtil.usleep(100 * 1000) -- Allow UI to update after typing

      -- Dismiss search keyboard dialog using stack-aware close_modal helper
      local success_close = close_modal()
      if not success_close then
        print("\nError: Failed to close keyboard search dialog!")
        break
      end

      local ks2, ku2 = ffiUtil.gettime()
      local k_duration = (ks2 - ks1) * 1000 + (ku2 - ku1) / 1000 -- in ms
      io.write(string.format(" Done (%.2f ms)", k_duration))
      table.insert(keysearch_durations, k_duration)
    end

    -- 3. Simulate book dogear bookmark toggle every 15 pages
    if target_page % 15 == 0 then
      io.write(" [Toggle Bookmark]...")
      io.stdout:flush()
      local bs1, bu1 = ffiUtil.gettime()

      -- Trigger toggle
      local success_bookmark = http_get(BASE_URL .. "/broadcast/ToggleBookmark")
      if not success_bookmark then
        print("\nError: Failed to toggle page bookmark!")
        break
      end

      -- Sleep 50ms to allow settings settings metadata flush to disk
      ffiUtil.usleep(50 * 1000)

      local bs2, bu2 = ffiUtil.gettime()
      local b_duration = (bs2 - bs1) * 1000 + (bu2 - bu1) / 1000 -- in ms
      io.write(string.format(" Done (%.2f ms)", b_duration))
      table.insert(bookmark_durations, b_duration)
    end

    print("") -- Complete line
  end

  return {
    turns = page_durations,
    dict = dict_durations,
    keydict = keydict_durations,
    keysearch = keysearch_durations,
    bookmark = bookmark_durations,
  }

end

local function get_children(pid)
  local children = {}
  local p = io.popen("pgrep -P " .. pid)
  if p then
    for child in p:lines() do
      local c = tonumber(child)
      if c then
        table.insert(children, c)
      end
    end
    p:close()
  end
  return children
end

local function kill_recursive(pid)
  local children = get_children(pid)
  for _, child in ipairs(children) do
    kill_recursive(child)
  end
  os.execute("kill -9 " .. pid .. " 2>/dev/null")
end

local function calculate_metrics(durations)
  local count = #durations
  if count == 0 then
    return nil
  end

  local total = 0
  local min_val = durations[1]
  local max_val = durations[1]
  for _, v in ipairs(durations) do
    total = total + v
    if v < min_val then
      min_val = v
    end
    if v > max_val then
      max_val = v
    end
  end

  local avg = total / count
  local variance_sum = 0
  for _, v in ipairs(durations) do
    variance_sum = variance_sum + (v - avg) ^ 2
  end

  local stddev = 0
  if count > 1 then
    stddev = math.sqrt(variance_sum / (count - 1))
  end

  return {
    count = count,
    total = total,
    min_val = min_val,
    max_val = max_val,
    avg = avg,
    stddev = stddev,
  }
end

local function print_comparative_report(results)
  print(
    "\n============================================================================================================================================="
  )
  print(
    "                                                 KOREADER PAGINATION COMPARATIVE BENCHMARK HARNESS"
  )
  print(
    "============================================================================================================================================="
  )
  print(
    string.format(
      "%-19s | %-6s | %-5s | %-12s | %-4s | %-12s | %-7s | %-12s | %-9s | %-12s | %-4s | %-12s",
      "Document Path",
      "Format",
      "Turns",
      "Avg Turn Lat",
      "Dict",
      "Avg Dict Lat",
      "KeyDict",
      "Avg KeyDict",
      "KeySearch",
      "Avg KeySrch",
      "Book",
      "Avg Book Lat"
    )
  )
  print(
    "---------------------------------------------------------------------------------------------------------------------------------------------"
  )
  for _, res in ipairs(results) do
    local ext = res.book_path:match("%.(%w+)$") or "unknown"
    if res.metrics then
      local turn_count = res.metrics.turns and res.metrics.turns.count or 0
      local turn_avg = res.metrics.turns
          and string.format("%.2f ms", res.metrics.turns.avg)
        or "N/A"

      local dict_count = res.metrics.dict and res.metrics.dict.count or 0
      local dict_avg = dict_count > 0
          and string.format("%.2f ms", res.metrics.dict.avg)
        or "N/A"

      local keydict_count = res.metrics.keydict and res.metrics.keydict.count
        or 0
      local keydict_avg = keydict_count > 0
          and string.format("%.2f ms", res.metrics.keydict.avg)
        or "N/A"

      local keysearch_count = res.metrics.keysearch and res.metrics.keysearch.count
        or 0
      local keysearch_avg = keysearch_count > 0
          and string.format("%.2f ms", res.metrics.keysearch.avg)
        or "N/A"

      local book_count = res.metrics.bookmark and res.metrics.bookmark.count
        or 0
      local book_avg = book_count > 0
          and string.format("%.2f ms", res.metrics.bookmark.avg)
        or "N/A"

      print(
        string.format(
          "%-19s | %-6s | %-5d | %-12s | %-4d | %-12s | %-7d | %-12s | %-9d | %-12s | %-4d | %-12s",
          res.book_path,
          ext:upper(),
          turn_count,
          turn_avg,
          dict_count,
          dict_avg,
          keydict_count,
          keydict_avg,
          keysearch_count,
          keysearch_avg,
          book_count,
          book_avg
        )
      )
    else
      print(
        string.format(
          "%-19s | %-6s | %-5s | %-12s | %-4s | %-12s | %-7s | %-12s | %-9s | %-12s | %-4s | %-12s",
          res.book_path,
          ext:upper(),
          "0",
          "CRASHED/FAIL",
          "0",
          "N/A",
          "0",
          "N/A",
          "0",
          "N/A",
          "0",
          "N/A"
        )
      )
    end
  end
  print(
    "============================================================================================================================================="
  )
end

local function run_remote_cmd(cmd)
  if IS_LOCAL_IP then
    return os.execute(cmd)
  else
    local remote_cmd = string.format("ssh %s %q", SSH_TARGET, cmd)
    return os.execute(remote_cmd)
  end
end

local function copy_to_device(local_path, remote_path)
  if IS_LOCAL_IP then
    local cp_cmd = string.format("cp %s %s", local_path, remote_path)
    return os.execute(cp_cmd)
  else
    local scp_cmd = string.format("scp %s %s:%s", local_path, SSH_TARGET, remote_path)
    return os.execute(scp_cmd)
  end
end

local function wait_for_server_up()
  local start_secs, start_usecs = ffiUtil.gettime()
  while true do
    local now_secs, now_usecs = ffiUtil.gettime()
    local elapsed = now_secs - start_secs + (now_usecs - start_usecs) / 1000000
    if elapsed >= 10 then -- 10 seconds timeout is plenty
      return false
    end
    local success = http_get(BASE_URL .. "/")
    if success then
      return true
    end
    ffiUtil.usleep(100 * 1000) -- 100ms
  end
end

local function open_book_on_device(book_path)
  -- Use double-quotes to protect single quotes (apostrophes) inside paths, and URL-encode
  local quoted_path = '"' .. book_path .. '"'

  print("[*] Enforcing File Manager home screen context via onHome...")
  pcall(http_get, BASE_URL .. "/ui/onHome/")

  -- Sleep 500ms to allow the old Reader session to teardown and server to stop if applicable
  ffiUtil.usleep(500 * 1000)

  -- Wait for the File Manager server session to become responsive
  if not wait_for_server_up() then
    error("Target device HTTP server did not become responsive after returning to home.")
  end

  print("[*] Active screen: File Manager. Opening document...")
  local url = BASE_URL .. "/ui/openFile/" .. url_encode(quoted_path)
  local success_open = http_get(url)
  if not success_open then
    error("Failed to send openFile command to target device!")
  end
end

local function start_emulator(book_path)
  if IS_REAL_DEVICE then
    local filename = book_path:match("([^/]+)$")
    local remote_path = DEVICE_DIR .. "/" .. filename
    local remote_sdr = remote_path:gsub("%.%w+$", ".sdr")

    print("[*] Preparing target device...")
    run_remote_cmd(string.format("mkdir -p %s", DEVICE_DIR))
    run_remote_cmd(string.format("rm -rf %s", remote_sdr))

    print(string.format("[*] Copying book to device: %s -> %s", book_path, remote_path))
    local ok = copy_to_device(book_path, remote_path)
    if ok ~= 0 and ok ~= true then
      error("Failed to copy book to device via scp!")
    end

    print("\n----------------------------------------------------------------------------------")
    print("OPENING DOCUMENT ON TARGET DEVICE: " .. remote_path)
    print("----------------------------------------------------------------------------------")

    open_book_on_device(remote_path)

    -- Wait for the session to load the document!
    local total_pages = wait_for_ready()
    return nil, total_pages -- No local PID!
  else
    -- Forcefully wipe out any pre-existing book SDR metadata state to force the document to open pristine-clean on page 1
    local book_sdr = book_path:gsub("%.%w+$", ".sdr")
    os.execute("rm -rf " .. book_sdr)

    setup_environment()

    local emulator_cmd
    if HEADFUL then
      -- Launch natively on host display with full hardware GPU/OpenGL acceleration (use %q to quote shell argument safely)
      emulator_cmd = string.format(
        "HOME=%s KO_MULTIUSER=1 ./run.sh %q > %s 2>&1 & echo $!",
        BENCHMARK_HOME,
        book_path,
        EMULATOR_LOG_PATH
      )
    else
      -- Launch headlessly under xvfb-run with forced software rendering to bypass sandboxed workstation freezes (use %q to quote shell argument safely)
      emulator_cmd = string.format(
        "HOME=%s KO_MULTIUSER=1 SDL_RENDER_DRIVER=software xvfb-run -a ./run.sh %q > %s 2>&1 & echo $!",
        BENCHMARK_HOME,
        book_path,
        EMULATOR_LOG_PATH
      )
    end

    print(
      "\n----------------------------------------------------------------------------------"
    )
    print("LAUNCHING EMULATOR SESSION WITH TARGET: " .. book_path)
    print(
      "----------------------------------------------------------------------------------"
    )

    local pipe = io.popen(emulator_cmd)
    local pid = tonumber(pipe:read("*line"))
    pipe:close()

    if not pid then
      error("Failed to retrieve emulator background PID.")
    end

    -- Wait for the first document to be ready
    local total_pages = wait_for_ready()
    return pid, total_pages
  end
end

local function open_document_in_session(book_path)
  if IS_REAL_DEVICE then
    local filename = book_path:match("([^/]+)$")
    local remote_path = DEVICE_DIR .. "/" .. filename
    local remote_sdr = remote_path:gsub("%.%w+$", ".sdr")

    print("[*] Preparing target device for next document...")
    run_remote_cmd(string.format("rm -rf %s", remote_sdr))

    print(string.format("[*] Copying book to device: %s -> %s", book_path, remote_path))
    local ok = copy_to_device(book_path, remote_path)
    if ok ~= 0 and ok ~= true then
      error("Failed to copy book to device via scp!")
    end

    print("\n----------------------------------------------------------------------------------")
    print("SWITCHING TARGET DOCUMENT ON DEVICE: " .. remote_path)
    print("----------------------------------------------------------------------------------")

    open_book_on_device(remote_path)

    -- Wait 1.5 seconds for old document close and new startup routines to initialize
    ffiUtil.usleep(1500 * 1000)

    -- Wait for the new session to become ready and load the document!
    local total_pages = wait_for_ready()
    return total_pages
  else
    -- Wiping target book sdr state first (to force start from page 1!)
    local book_sdr = book_path:gsub("%.%w+$", ".sdr")
    os.execute("rm -rf " .. book_sdr)

    print(
      "\n----------------------------------------------------------------------------------"
    )
    print("SWITCHING TARGET DOCUMENT IN SESSION: " .. book_path)
    print(
      "----------------------------------------------------------------------------------"
    )

    -- Send open file command (enclosed in double quotes and URL-encoded to protect spaces and special characters)
    local url = BASE_URL .. "/ui/showReader/" .. url_encode('"' .. book_path .. '"')
    pcall(http_get, url) -- ignore connection close errors on session transfer!

    -- Wait 1.5 seconds for old document close and new startup routines to initialize
    ffiUtil.usleep(1500 * 1000)

    -- Wait for the new session to become ready and load the document!
    local total_pages = wait_for_ready()
    return total_pages
  end
end

local function stop_emulator(pid)
  print("Shutting down emulator session gracefully...")
  pcall(http.request, BASE_URL .. "/UIManager/quit/")

  -- wait 2 seconds for graceful exit, otherwise kill forcefully
  local graceful_exit = false
  for i = 1, 10 do
    local p = io.popen("ps -p " .. pid)
    local res = p:read("*all")
    p:close()
    if not res:find(tostring(pid)) then
      graceful_exit = true
      break
    end
    ffiUtil.usleep(200 * 1000) -- 200ms
  end

  if not graceful_exit then
    print(
      "Emulator did not exit gracefully, killing process group forcefully..."
    )
    kill_recursive(pid)
  end
  print("Emulator session stopped.")
end

local function is_process_alive(pid)
  local p = io.popen("ps -p " .. pid)
  local res = p:read("*all")
  p:close()
  return res:find(tostring(pid)) ~= nil
end

local function main()
  print(
    "Starting multi-document comparative benchmarking suite (active session single-run switcher)..."
  )
  local results = {}
  local pid
  local ok_main, err_main = pcall(function()
    for idx, doc in ipairs(TARGET_DOCUMENTS) do
      local durations
      local ok, err
      local entry = { book_path = doc }

      if idx == 1 then
        -- 1. Start emulator on the first target book
        local total_pages
        ok, err = pcall(function()
          pid, total_pages = start_emulator(doc)
          durations = run_benchmark(total_pages)
        end)
      else
        -- 2. Open subsequent target books directly in the running session
        local is_alive = IS_REAL_DEVICE or (pid and is_process_alive(pid))
        if is_alive then
          ok, err = pcall(function()
            local total_pages = open_document_in_session(doc)
            durations = run_benchmark(total_pages)
          end)
        else
          ok = false
          err = "Emulator session is dead."
        end
      end

      if ok and durations then
        entry.metrics = {
          turns = calculate_metrics(durations.turns),
          dict = calculate_metrics(durations.dict),
          keydict = calculate_metrics(durations.keydict),
          keysearch = calculate_metrics(durations.keysearch),
          bookmark = calculate_metrics(durations.bookmark),
        }
      else
        print(
          string.format("\nBenchmark failed for %s: %s", doc, tostring(err)),
          io.stderr
        )
        if pid and is_process_alive(pid) then
          print("Tail of emulator logs:")
          os.execute("tail -n 20 " .. EMULATOR_LOG_PATH)
        end
      end
      table.insert(results, entry)
    end
  end)

  -- Always stop the running emulator session at the end of execution!
  if pid then
    pcall(stop_emulator, pid)
  end

  if not ok_main then
    print("\nGlobal execution failed: " .. tostring(err_main), io.stderr)
  end

  print_comparative_report(results)
end

main()
