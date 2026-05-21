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
  "test/sample.txt",
}
-- Headless vs Headful viewport mode configuration
local HEADFUL = false
for i = 1, #arg do
  if arg[i] == "--headful" then
    HEADFUL = true
  end
end
local env_headful = os.getenv("HEADFUL")
if env_headful == "1" or env_headful == "true" then
  HEADFUL = true
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

local function run_benchmark(total_pages)
  print(
    string.format(
      "\nStarting benchmark: Paging through %d pages...",
      total_pages
    )
  )
  local page_durations = {}

  local current_page = 1
  for turn = 1, total_pages - 1 do
    local target_page = current_page + 1
    io.write(
      string.format("Turning to page %d/%d...", target_page, total_pages)
    )
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

    print(string.format(" Done in %.2f ms", duration))
    table.insert(page_durations, duration)
    current_page = target_page
  end

  return page_durations
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
    "\n=================================================================================="
  )
  print("                KOREADER PAGINATION COMPARATIVE BENCHMARK HARNESS")
  print(
    "=================================================================================="
  )
  print(
    string.format(
      "%-25s | %-6s | %-5s | %-12s | %-18s | %-8s",
      "Document Path",
      "Format",
      "Turns",
      "Avg Latency",
      "Min/Max Latency",
      "StdDev"
    )
  )
  print(
    "----------------------------------------------------------------------------------"
  )
  for _, res in ipairs(results) do
    local ext = res.book_path:match("%.(%w+)$") or "unknown"
    if res.metrics then
      local min_max =
        string.format("%.1f/%.1f ms", res.metrics.min_val, res.metrics.max_val)
      print(
        string.format(
          "%-25s | %-6s | %-5d | %8.2f ms | %-18s | %6.2f ms",
          res.book_path,
          ext:upper(),
          res.metrics.count,
          res.metrics.avg,
          min_max,
          res.metrics.stddev
        )
      )
    else
      print(
        string.format(
          "%-25s | %-6s | %-5s | %-12s | %-18s | %-8s",
          res.book_path,
          ext:upper(),
          "0",
          "CRASHED/FAIL",
          "N/A",
          "N/A"
        )
      )
    end
  end
  print(
    "=================================================================================="
  )
end

local function run_single_document_benchmark(book_path)
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
      entry.metrics = calculate_metrics(durations)
    end
    table.insert(results, entry)
  end
  print_comparative_report(results)
end

main()
