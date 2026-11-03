local spy = require("luassert.spy")

describe("systemstat", function()
  local SystemStatWidget
  local orig_uimanager_show
  local spy_uimanager_show
  local mock_bookinfomanager
  local orig_getPowerDevice

  setup(function()
    require("commonrequire")

    -- Monkey-patch real Device if needed
    local Device = require("device")
    orig_getPowerDevice = Device.getPowerDevice
    Device.getPowerDevice = function()
      return {
        isCharging = function()
          return true
        end,
        isCharged = function()
          return true
        end,
        isAuxBatteryConnected = function()
          return false
        end,
        isAuxCharging = function()
          return false
        end,
        isAuxCharged = function()
          return false
        end,
      }
    end

    -- Monkey-patch UIManager.show
    local UIManager = require("ui/uimanager")
    orig_uimanager_show = UIManager.show
    spy_uimanager_show = spy.new(function() end)
    UIManager.show = spy_uimanager_show

    -- Mock BookInfoManager
    mock_bookinfomanager = {
      getBookCount = spy.new(function()
        return 123
      end),
    }
    package.loaded["bookinfomanager"] = mock_bookinfomanager

    -- Load SystemStatWidget using dofile to avoid path resolution issues in tests
    SystemStatWidget = dofile("plugins/systemstat.koplugin/main.lua")
  end)

  teardown(function()
    local Device = require("device")
    Device.getPowerDevice = orig_getPowerDevice
    local UIManager = require("ui/uimanager")
    UIManager.show = orig_uimanager_show
    package.loaded["bookinfomanager"] = nil
  end)

  it("shows indexed files count in statistics", function()
    local menu = {
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
    })

    -- Trigger statistics display
    widget:onShowSysStatistics()

    -- Verify UIManager:show was called with KeyValuePage
    assert.spy(spy_uimanager_show).was.called(1)
    local key_value_page = spy_uimanager_show.calls[1].refs[2]
    assert.is_not_nil(key_value_page)

    -- Verify KeyValuePage title
    assert.equal("System statistics", key_value_page.title)

    -- Verify "Indexed files" is in kv_pairs with value 123
    local found = false
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  Indexed files" then -- Note the leading spaces in gettext
        assert.equal(123, pair[2])
        found = true
        break
      end
    end
    assert.is_true(found, "Indexed files entry not found in system statistics")
  end)

  it("shows current Lua runtime before device model in statistics", function()
    local gettext = require("gettext")
    local orig_arg = _G.arg

    finally(function()
      _G.arg = orig_arg
    end)

    local cases = {
      {
        arg = { [-1] = "./lua", [0] = "reader.lua" },
        expected = "./lua",
      },
      {
        arg = { [-1] = "./luajit", [0] = "reader.lua" },
        expected = "./luajit",
      },
      {
        arg = { [-2] = "./luajit", [-1] = "-O3", [0] = "./reader.lua" },
        expected = "./luajit -O3",
      },
    }

    local menu = {
      registerToMainMenu = spy.new(function() end),
    }

    for _, c in ipairs(cases) do
      _G.arg = c.arg
      local widget = SystemStatWidget:new({
        ui = {
          menu = menu,
        },
      })
      widget:onShowSysStatistics()

      local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
      assert.is_not_nil(key_value_page)

      local runtime_idx, model_idx
      for idx, pair in ipairs(key_value_page.kv_pairs) do
        if pair[1] == "  " .. gettext("Runtime") then
          runtime_idx = idx
          assert.are.equal(c.expected, pair[2])
        elseif pair[1] == "  " .. gettext("Device model") then
          model_idx = idx
        end
      end

      assert.is_not_nil(runtime_idx, "Runtime entry not found in system statistics")
      assert.is_not_nil(model_idx, "Device model entry not found in system statistics")
      assert.are.equal(model_idx - 1, runtime_idx, "Runtime should appear immediately before Device model")
    end
  end)

  it("shows 0 for background processes when none are running", function()
    local ffiUtil = require("ffi/util")
    local gettext = require("gettext")
    ffiUtil.subprocesses = {}

    local menu = {
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
    })
    widget:onShowSysStatistics()

    local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    local bg_entry = nil
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  " .. gettext("Background processes") then
        bg_entry = pair
        break
      end
    end
    assert.is_not_nil(bg_entry)
    assert.are.equal(0, bg_entry[2])
    assert.is_nil(bg_entry.callback)
  end)

  it("shows count and tap to view for background processes when running", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local ffiUtil = require("ffi/util")
    local gettext = require("gettext")
    local T = ffiUtil.template

    local start = os.time() - 5
    ffiUtil.subprocesses = {
      [101] = {
        pid = 101,
        cmd = "test_script.lua:10",
        start_time = start,
        output = "hello world",
      },
      [102] = {
        pid = 102,
        cmd = "empty_script.lua:20",
        start_time = start,
        output = "",
      },
    }

    local menu = {
      registerToMainMenu = spy.new(function() end),
    }
    local widget = SystemStatWidget:new({
      ui = {
        menu = menu,
      },
    })
    widget:onShowSysStatistics()

    local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    local bg_entry = nil
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[1] == "  " .. gettext("Background processes") then
        bg_entry = pair
        break
      end
    end
    assert.is_not_nil(bg_entry)
    assert.are.equal(T(gettext("%1 (tap to view)"), 2), bg_entry[2])
    assert.is_function(bg_entry.callback)

    -- Tap the background processes entry
    bg_entry.callback()
    local proc_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.is_not_nil(proc_page)
    assert.are.equal(gettext("Background processes"), proc_page.title)
    assert.are.equal(2, #proc_page.kv_pairs)

    -- First entry: pid 101 (sorted by pid)
    local p1 = proc_page.kv_pairs[1]
    assert.are.equal("[101] test_script.lua:10", p1[1])
    assert.is_truthy(p1[2]:match("^%d+:%d%d:%d%d$"))
    assert.is_function(p1.callback)

    -- Tap p1 (has output)
    p1.callback()
    local viewer1 = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.are.equal("[101] test_script.lua:10", viewer1.title)
    assert.are.equal("hello world", viewer1.text)
    assert.are.equal(Blitbuffer.COLOR_BLACK, viewer1.fgcolor)
    assert.are.equal("code", viewer1.text_type)

    -- Second entry: pid 102 (empty output)
    local p2 = proc_page.kv_pairs[2]
    assert.are.equal("[102] empty_script.lua:20", p2[1])
    assert.is_function(p2.callback)

    -- Tap p2 (empty output -> shows gettext("No output.") in COLOR_DARK_GRAY)
    p2.callback()
    local viewer2 = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.are.equal("[102] empty_script.lua:20", viewer2.title)
    assert.are.equal(gettext("No output."), viewer2.text)
    assert.are.equal(Blitbuffer.COLOR_DARK_GRAY, viewer2.fgcolor)
    assert.are.equal("code", viewer2.text_type)

    ffiUtil.subprocesses = {}
  end)

  it("collects system info without popen and normalizes process processor usage", function()
    local Device = require("device")
    local gettext = require("gettext")
    local lfs = require("libs/libkoreader-lfs")
    local time = require("ui/time")

    local orig_io_open = io.open
    local orig_io_popen = io.popen
    local orig_lfs_dir = lfs.dir
    local orig_boottime = time.boottime_or_realtime_coarse
    local orig_monotonic = time.monotonic
    local orig_can_suspend = Device.canSuspend
    local orig_total_suspend = Device.total_suspend_time

    finally(function()
      io.open = orig_io_open
      io.popen = orig_io_popen
      lfs.dir = orig_lfs_dir
      time.boottime_or_realtime_coarse = orig_boottime
      time.monotonic = orig_monotonic
      Device.canSuspend = orig_can_suspend
      Device.total_suspend_time = orig_total_suspend
    end)

    local mock_files = {
      ["/proc/stat"] = table.concat({
        "cpu  1000 100 300 5000 200 50 350 0 0 0",
        "cpu0 500 50 150 2500 100 25 175 0 0 0",
        "cpu1 500 50 150 2500 100 25 175 0 0 0",
        "intr 12345",
      }, "\n"),
      ["/proc/meminfo"] = table.concat({
        "MemTotal:        524288 kB",
        "MemFree:         131072 kB",
        "MemAvailable:    262144 kB",
      }, "\n"),
      ["/proc/loadavg"] = "0.25 0.50 0.75 1/120 1234",
      ["/proc/uptime"] = "1000.00 800.00",
      ["/proc/self/stat"] = "4242 (luajit) R 1 4242 4242 0 -1 4194304 100 0 0 0 200 100 30 20 20 0 4 0 12345 10485760 2560",
    }

    local function make_mock_file(content)
      local f = io.tmpfile()
      f:write(content)
      f:seek("set")
      return f
    end

    io.open = function(path, mode)
      if mock_files[path] then
        return make_mock_file(mock_files[path])
      end
      return orig_io_open(path, mode)
    end

    io.popen = function(cmd)
      if cmd:match("^df %-h") then
        return make_mock_file("")
      end
      error("Unexpected io.popen call: " .. tostring(cmd))
    end

    lfs.dir = function(path)
      if path == "/proc" then
        local entries = { ".", "..", "self", "1", "2", "100", "4242", "net", "sys" }
        local idx = 0
        return function()
          idx = idx + 1
          return entries[idx]
        end, nil
      end
      return orig_lfs_dir(path)
    end

    time.boottime_or_realtime_coarse = function()
      return time.s(1000)
    end
    local fresh_widget_cls = dofile("plugins/systemstat.koplugin/main.lua")

    -- 500s KOReader uptime, 250s suspend -> 250s KOReader awake
    -- 400s OS monotonic awake -> koreader_awake / monotonic = 0.625
    -- Process ticks: 200 + 100 + 30 + 20 = 350; cpu.total = 7000
    -- Normalized usage: 350 / (7000 * 0.625) * 100 = 8.00%
    time.boottime_or_realtime_coarse = function()
      return time.s(1500)
    end
    time.monotonic = function()
      return time.s(400)
    end
    Device.canSuspend = function()
      return true
    end
    Device.total_suspend_time = time.s(250)

    fresh_widget_cls
      :new({
        ui = {
          menu = {
            registerToMainMenu = spy.new(function() end),
          },
        },
      })
      :onShowSysStatistics()

    local key_value_page = spy_uimanager_show.calls[#spy_uimanager_show.calls].refs[2]
    assert.is_not_nil(key_value_page)

    local section = ""
    local values = {}
    for _, pair in ipairs(key_value_page.kv_pairs) do
      if pair[2] == "" then
        section = pair[1]
      else
        values[section .. "::" .. pair[1]] = pair[2]
      end
    end

    assert.are.equal(4, values[gettext("System information") .. "::" .. gettext("  Number of processes")])
    assert.are.equal(2, values[gettext("System information") .. "::" .. "  " .. gettext("Number of processors")])
    assert.are.equal("25.00", values[gettext("System information") .. "::" .. gettext("  Processor usage %")])
    assert.are.equal("50.00", values[gettext("System information") .. "::" .. "  " .. gettext("5 minutes usage %")])
    assert.are.equal("75.00", values[gettext("System information") .. "::" .. "  " .. gettext("15 minutes usage %")])
    assert.are.equal(350, values[gettext("Process") .. "::" .. "  " .. gettext("Total ticks")])
    assert.are.equal("8.00", values[gettext("Process") .. "::" .. gettext("  Processor usage %")])
  end)
end)
