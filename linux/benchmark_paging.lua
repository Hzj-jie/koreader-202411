#!/usr/bin/env ./luajit
-- Comparative pagination benchmark runner

require("setupkoenv")

local ffiUtil = require("ffi/util")
local http = require("socket.http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")

local BENCHMARK_HOME = "/tmp/koreader_benchmark"
local PORT = 8088
local BASE_URL = string.format("http://localhost:%d/koreader", PORT)

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

-- CLI flag overrides
for i = 1, #arg do
  if arg[i] == "--headful" then
    HEADFUL = true
  elseif arg[i] == "--headless" then
    HEADFUL = false
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
  print("Waiting for KOReader emulator to boot and HTTP server to start...")
  local start_secs, start_usecs = ffiUtil.gettime()
  local url = BASE_URL .. "/ui/document/getPageCount/"

  while true do
    local now_secs, now_usecs = ffiUtil.gettime()
    local elapsed = now_secs - start_secs + (now_usecs - start_usecs) / 1000000
    if elapsed >= 15 then
      break
    end

    local success, val = get_json_val(url)
    if success and type(val) == "number" and val > 0 then
      print(
        string.format(
          "Server is ready! Document loaded successfully. Total pages: %d",
          val
        )
      )
      return val
    end
    ffiUtil.usleep(200 * 1000) -- sleep for 200ms
  end

  error("KOReader emulator did not start up within 15 seconds.")
end

local function is_modal_open()
  local success, code = http_get(BASE_URL .. "/UIManager/_window_stack/2")
  if success then
    -- Returned 200 OK (widget serialized successfully!)
    return true
  end
  if code == "500" then
    -- Returned 500 Internal Error, indicating index 2 exists but is a recursive layout structure
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

  -- 1. Trigger "Exit" event (closes virtual keyboard on both branches, or master DictQuickLookup)
  http_get(BASE_URL .. "/event/Exit")

  -- Poll for close (up to 500ms timeout)
  if wait_for_modal_close() then
    return true
  end

  -- 2. Trigger "CloseDialog" event (closes InputDialog modal window on both branches)
  http_get(BASE_URL .. "/event/CloseDialog")

  -- Poll for close (up to 500ms timeout)
  if wait_for_modal_close() then
    return true
  end

  -- 3. Trigger baseline "Close" event (closes baseline DictQuickLookup popup)
  local success_close = http_get(BASE_URL .. "/event/Close")
  if not success_close then
    print("\nError: Failed to send baseline Close event!")
    return false
  end

  -- Poll for close (up to 500ms timeout)
  if wait_for_modal_close() then
    return true
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
  local page_durations = {}
  local dict_durations = {}
  local keydict_durations = {}
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
      ffiUtil.usleep(10 * 1000) -- Poll very fast (10ms)
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
        http_get(BASE_URL .. "/broadcast/LookupWord/Shakespeare")
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
          .. "/UIManager/_window_stack/2/widget/_input_widget/addChars/Shakespeare%0A"
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
    bookmark = bookmark_durations,
  }
end

local function shutdown_emulator()
  print("Shutting down emulator gracefully...")
  pcall(http.request, BASE_URL .. "/UIManager/quit/")
  print("Shutdown complete.")
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
    "\n====================================================================================================================="
  )
  print(
    "                                 KOREADER PAGINATION COMPARATIVE BENCHMARK HARNESS"
  )
  print(
    "====================================================================================================================="
  )
  print(
    string.format(
      "%-19s | %-6s | %-5s | %-12s | %-4s | %-12s | %-7s | %-12s | %-4s | %-12s",
      "Document Path",
      "Format",
      "Turns",
      "Avg Turn Lat",
      "Dict",
      "Avg Dict Lat",
      "KeyDict",
      "Avg KeyDict",
      "Book",
      "Avg Book Lat"
    )
  )
  print(
    "---------------------------------------------------------------------------------------------------------------------"
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

      local book_count = res.metrics.bookmark and res.metrics.bookmark.count
        or 0
      local book_avg = book_count > 0
          and string.format("%.2f ms", res.metrics.bookmark.avg)
        or "N/A"

      print(
        string.format(
          "%-19s | %-6s | %-5d | %-12s | %-4d | %-12s | %-7d | %-12s | %-4d | %-12s",
          res.book_path,
          ext:upper(),
          turn_count,
          turn_avg,
          dict_count,
          dict_avg,
          keydict_count,
          keydict_avg,
          book_count,
          book_avg
        )
      )
    else
      print(
        string.format(
          "%-19s | %-6s | %-5s | %-12s | %-4s | %-12s | %-7s | %-12s | %-4s | %-12s",
          res.book_path,
          ext:upper(),
          "0",
          "CRASHED/FAIL",
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
    "====================================================================================================================="
  )
end

local function run_single_document_benchmark(book_path)
  -- Forcefully wipe out any pre-existing book SDR metadata state to force the document to open pristine-clean on page 1
  local book_sdr = book_path:gsub("%.%w+$", ".sdr")
  os.execute("rm -rf " .. book_sdr)

  setup_environment()

  local emulator_cmd
  if HEADFUL then
    -- Launch natively on host display with full hardware GPU/OpenGL acceleration
    emulator_cmd = string.format(
      "HOME=%s KO_MULTIUSER=1 ./run.sh %s > /tmp/benchmark_koreader_emulator.log 2>&1 & echo $!",
      BENCHMARK_HOME,
      book_path
    )
  else
    -- Launch headlessly under xvfb-run with forced software rendering to bypass sandboxed workstation freezes
    emulator_cmd = string.format(
      "HOME=%s KO_MULTIUSER=1 SDL_RENDER_DRIVER=software xvfb-run -a ./run.sh %s > /tmp/benchmark_koreader_emulator.log 2>&1 & echo $!",
      BENCHMARK_HOME,
      book_path
    )
  end

  print(
    "\n----------------------------------------------------------------------------------"
  )
  print("LAUNCHING EMULATOR TARGET: " .. book_path)
  print(
    "----------------------------------------------------------------------------------"
  )

  local pipe = io.popen(emulator_cmd)
  local pid = tonumber(pipe:read("*line"))
  pipe:close()

  if not pid then
    return nil, "Failed to retrieve emulator background PID."
  end

  local durations = {}
  local ok, err = pcall(function()
    local total_pages = wait_for_ready()
    durations = run_benchmark(total_pages)
  end)

  -- Clean up
  pcall(shutdown_emulator)
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

  if not ok then
    print(
      "\nBenchmark failed for " .. book_path .. ": " .. tostring(err),
      io.stderr
    )
    print("Tail of emulator logs:")
    os.execute("tail -n 20 /tmp/benchmark_koreader_emulator.log")
    return nil, err
  end

  return durations
end

local function main()
  print(
    "Starting multi-document comparative benchmarking suite (paging through the entire book)..."
  )
  local results = {}
  for _, doc in ipairs(TARGET_DOCUMENTS) do
    local durations = run_single_document_benchmark(doc)
    local entry = { book_path = doc }
    if durations then
      entry.metrics = {
        turns = calculate_metrics(durations.turns),
        dict = calculate_metrics(durations.dict),
        keydict = calculate_metrics(durations.keydict),
        bookmark = calculate_metrics(durations.bookmark),
      }
    end
    table.insert(results, entry)
  end
  print_comparative_report(results)
end

main()
