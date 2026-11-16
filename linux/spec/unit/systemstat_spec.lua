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

  it(
    "shows 1/5/15-min system workload as percentages while keeping per-process processor usage",
    function()
      local gettext = require("gettext")
      local stub = require("luassert.stub")
      local orig_io_open = io.open
      local popen_stub

      finally(function()
        io.open = orig_io_open
        if popen_stub then
          popen_stub:revert()
        end
      end)

      local function makeMockFile(content)
        local f = assert(io.tmpfile())
        f:write(content)
        f:seek("set")
        return f
      end

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
        ["/proc/loadavg"] = "0.25 0.50 0.75 1/120 1234\n",
        ["/proc/uptime"] = "1000.00 800.00\n",
        ["/proc/self/stat"] = "4242 (luajit) R 1 4242 4242 0 -1 4194304 100 0 0 0 200 100 30 20 20 0 4 0 12345 10485760 2560\n",
      }

      io.open = function(path, mode)
        if mock_files[path] then
          return makeMockFile(mock_files[path])
        end
        return orig_io_open(path, mode)
      end

      popen_stub = stub(io, "popen", function(cmd)
        if cmd:match("^cat /proc/stat") then
          return makeMockFile("3\n")
        elseif cmd:match("^ps %-e") then
          return makeMockFile("6\n")
        elseif cmd:match("^uptime") then
          return makeMockFile(" 0.25, 0.50, 0.75\n")
        elseif cmd:match("^df %-h") then
          return makeMockFile("")
        end
        error("Unexpected io.popen call: " .. tostring(cmd))
      end)

      SystemStatWidget:new({
        ui = {
          menu = {
            registerToMainMenu = spy.new(function() end),
          },
        },
      }):onShowSysStatistics()

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

      local sys_info = gettext("System information")
      assert.are.equal("25.00%", values[sys_info .. "::" .. "  " .. gettext("1-min system workload")])
      assert.are.equal("50.00%", values[sys_info .. "::" .. "  " .. gettext("5-min system workload")])
      assert.are.equal("75.00%", values[sys_info .. "::" .. "  " .. gettext("15-min system workload")])
      assert.is_nil(values[sys_info .. "::" .. gettext("  Processor usage %")])
      assert.is_nil(values[sys_info .. "::" .. "  " .. gettext("5 minutes usage %")])
      assert.is_nil(values[sys_info .. "::" .. "  " .. gettext("15 minutes usage %")])
      assert.are.equal("4.29", values[gettext("Process") .. "::" .. gettext("  Processor usage %")])
    end
  )

  it("verifies localized system workload strings in zh_CN and zh_TW", function()
    local gettext = require("gettext")
    finally(function()
      gettext.changeLang("C")
    end)

    gettext.changeLang("zh_CN")
    assert.are.equal("1分钟系统工作负载", gettext("1-min system workload"))
    assert.are.equal("5分钟系统工作负载", gettext("5-min system workload"))
    assert.are.equal("15分钟系统工作负载", gettext("15-min system workload"))
    assert.are.equal("  处理器使用率 %", gettext("  Processor usage %"))

    gettext.changeLang("zh_TW")
    assert.are.equal("1分鐘系統工作負載", gettext("1-min system workload"))
    assert.are.equal("5分鐘系統工作負載", gettext("5-min system workload"))
    assert.are.equal("15分鐘系統工作負載", gettext("15-min system workload"))
    assert.are.equal("  處理器用量百分比", gettext("  Processor usage %"))
  end)
end)
