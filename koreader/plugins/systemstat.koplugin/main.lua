local Device = require("device")
local Dispatcher = require("dispatcher")
local KeyValuePage = require("ui/widget/keyvaluepage")
local Math = require("optmath")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local time = require("ui/time")
local util = require("util")
local _ = require("gettext")

local function systemInfo()
  local result = {}
  do
    result.cpu = {
      user = 0,
      nice = 0,
      system = 0,
      idle = 0,
      io_wait = 0,
      hardirq = 0,
      softirq = 0,
    }
    local stat = io.open("/proc/stat", "r")
    assert(stat ~= nil)
    for line in stat:lines() do
      local t = util.splitToArray(line, " ")
      if #t > 0 and string.lower(t[1]) == "cpu" then
        if #t > 1 then
          result.cpu.user = tonumber(t[2])
        end
        if #t > 2 then
          result.cpu.nice = tonumber(t[3])
        end
        if #t > 3 then
          result.cpu.system = tonumber(t[4])
        end
        if #t > 4 then
          result.cpu.idle = tonumber(t[5])
        end
        if #t > 5 then
          result.cpu.io_wait = tonumber(t[6])
        end
        if #t > 6 then
          result.cpu.hardirq = tonumber(t[7])
        end
        if #t > 7 then
          result.cpu.softirq = tonumber(t[8])
        end
        break
      end
    end
    result.cpu.total = result.cpu.user
      + result.cpu.nice
      + result.cpu.system
      + result.cpu.idle
      + result.cpu.io_wait
      + result.cpu.hardirq
      + result.cpu.softirq
    stat:close()
  end

  do
    local handle = io.popen("cat /proc/stat | grep ^cpu | wc -l")
    assert(handle ~= nil)
    -- Exclude cpu line.
    result.cpu.count = tonumber(handle:read("*a")) - 1
  end

  do
    local meminfo = io.open("/proc/meminfo", "r")
    assert(meminfo ~= nil)
    result.memory = {
      total = 0,
      free = 0,
      available = 0,
    }
    for line in meminfo:lines() do
      local t = util.splitToArray(line, " ")
      if #t >= 2 then
        if string.lower(t[1]) == "memtotal:" then
          local n = tonumber(t[2])
          if n ~= nil then
            result.memory.total = n
          end
        elseif string.lower(t[1]) == "memfree:" then
          local n = tonumber(t[2])
          if n ~= nil then
            result.memory.free = n
          end
        elseif string.lower(t[1]) == "memavailable:" then
          local n = tonumber(t[2])
          if n ~= nil then
            result.memory.available = n
          end
        end
      end
    end
    meminfo:close()
  end

  do
    result.processes = {}
    local handle = io.popen("ps -e | wc -l")
    assert(handle ~= nil)
    -- Exclude ps and wc
    result.processes.count = tonumber(handle:read("*a")) - 2
  end

  do
    result.cpu.average = {}
    local handle = io.popen("uptime | sed 's/.*load average://g'")
    assert(handle ~= nil)
    for word in handle:read("*a"):gmatch("[^,%s]+") do
      table.insert(result.cpu.average, tonumber(word))
    end
  end

  do
    result.uptime = {
      sec = 0,
    }
    local file = io.open("/proc/uptime", "r")
    assert(file ~= nil)
    local t = util.splitToArray(file:read("*line"), " ")
    if #t > 0 then
      result.uptime.sec = tonumber(t[1])
    end
  end

  return result
end

local SystemStat = {
  start_time = time.realtime(),
  start_monotonic_time = time.boottime_or_realtime_coarse(),
  suspend_time = nil,
  resume_time = nil,
  wakeup_count = 0,
  sleep_count = 0,
  charge_count = 0,
  discharge_count = 0,
}

function SystemStat:init()
  if Device:isCervantes() or Device:isPocketBook() then
    self.storage_filter = "mmcblk"
  elseif Device:isKobo() then
    self.storage_filter = " /mnt/"
  elseif Device:isKindle() then
    self.storage_filter = "' /mnt/us$'"
  elseif Device:isSDL() then
    self.storage_filter = "/dev/sd"
  end

  -- Account for a start-up mid-charge
  local powerd = Device:getPowerDevice()
  if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
    if powerd:isAuxCharging() and not powerd:isAuxCharged() then
      self.charge_count = self.charge_count + 1
    end
  else
    if powerd:isCharging() and not powerd:isCharged() then
      self.charge_count = self.charge_count + 1
    end
  end
end

function SystemStat:put(p)
  table.insert(self.kv_pairs, p)
end

function SystemStat:putSeparator()
  self.kv_pairs[#self.kv_pairs].separator = true
end

function SystemStat:appendCounters()
  self:put({
    _("KOReader started at"),
    datetime.secondsToDateTime(time.to_s(self.start_time), nil, true),
  })
  if self.suspend_time then
    self:put({
      "  " .. _("Last suspend time"),
      datetime.secondsToDateTime(time.to_s(self.suspend_time), nil, true),
    })
  end
  if self.resume_time then
    self:put({
      "  " .. _("Last resume time"),
      datetime.secondsToDateTime(time.to_s(self.resume_time), nil, true),
    })
  end
  local uptime = time.boottime_or_realtime_coarse() - self.start_monotonic_time
  local suspend = 0
  if Device:canSuspend() then
    suspend = Device.total_suspend_time
  end
  local standby = 0
  if Device:canStandby() then
    standby = Device.total_standby_time
  end
  self:put({
    "  " .. _("Up time"),
    datetime.secondsToClockDuration("", time.to_s(uptime), false, true),
  })
  if Device:canSuspend() or Device:canStandby() then
    local awake = uptime - suspend - standby
    self:put({
      "  " .. _("Time spent awake"),
      datetime.secondsToClockDuration("", time.to_s(awake), false, true)
        .. " ("
        .. Math.round((awake / uptime) * 100)
        .. "%)",
    })
  end
  if Device:canSuspend() then
    self:put({
      "  " .. _("Time in suspend"),
      datetime.secondsToClockDuration("", time.to_s(suspend), false, true)
        .. " ("
        .. Math.round((suspend / uptime) * 100)
        .. "%)",
    })
  end
  if Device:canStandby() then
    self:put({
      "  " .. _("Time in standby"),
      datetime.secondsToClockDuration("", time.to_s(standby), false, true)
        .. " ("
        .. Math.round((standby / uptime) * 100)
        .. "%)",
    })
  end
  self:putSeparator()
  self:put({ _("Counters"), "" })
  -- TODO: Remove the wakeup_count and the assertion.
  if G_defaults:isTrue("DEV_MODE") then
    assert(self.wakeup_count == self.sleep_count)
  end
  -- @translators The number of "sleeps", that is the number of times the device has entered standby. This could also be translated as a rendition of a phrase like "entered sleep".
  self:put({
    _("  Wake-ups") .. " / " .. _("  sleeps"):gsub("^%s+", ""),
    self.wakeup_count,
  })
  -- TODO: Remove the charge_count and the assertion.
  if G_defaults:isTrue("DEV_MODE") then
    assert(
      self.charge_count == self.discharge_count
        or self.charge_count == self.discharge_count + 1
    )
  end
  self:put({ _("  Discharge cycles"), self.discharge_count })
  -- no localization.
  self:put({ _("  Background jobs"), #require("pluginshare").backgroundJobs })
end

function SystemStat:appendSystemInfo()
  self:put({ _("System information"), "" })
  -- Need localization
  self:put({
    _("  Number of processes"),
    self.sys_stat.processes.count,
  })
  self:put({
    "  " .. _("Up time"),
    datetime.secondsToClockDuration("", self.sys_stat.uptime.sec, false, true),
  })
  local uptime = self.sys_stat.uptime.sec
  if Device:canSuspend() or Device:canStandby() then
    -- Assume getconf CLK_TCK is 100.
    local awake = self.sys_stat.cpu.total / 100 / self.sys_stat.cpu.count
    self:put({
      "  " .. _("Time spent awake"),
      datetime.secondsToClockDuration("", awake, false, true)
        .. " ("
        .. Math.round((awake / uptime) * 100)
        .. "%)",
    })
  end
  if Device:canSuspend() then
    -- Assume getconf CLK_TCK is 100.
    local suspend = self.sys_stat.uptime.sec
      - self.sys_stat.cpu.total / 100 / self.sys_stat.cpu.count
    self:put({
      "  " .. _("Time in suspend"),
      datetime.secondsToClockDuration("", suspend, false, true)
        .. " ("
        .. Math.round((suspend / uptime) * 100)
        .. "%)",
    })
  end
  -- Need localization
  self:put({ _("  Number of processors"), self.sys_stat.cpu.count })
  -- @translators Ticks is a highly technical term. See https://superuser.com/a/101202 The correct translation is likely to simply be "ticks".
  self:put({
    _("  Total ticks (million)"),
    string.format("%.2f", self.sys_stat.cpu.total * (1 / 1000000)),
  })
  -- @translators Ticks is a highly technical term. See https://superuser.com/a/101202 The correct translation is likely to simply be "ticks".
  self:put({
    _("  Idle ticks (million)"),
    string.format("%.2f", self.sys_stat.cpu.idle * (1 / 1000000)),
  })
  if #self.sys_stat.cpu.average > 0 then
    self:put({
      _("  Processor usage %"),
      string.format("%.2f", self.sys_stat.cpu.average[1] * 100),
    })
  end
  if #self.sys_stat.cpu.average > 1 then
    -- Need localization
    self:put({
      _("  5 minutes usage %"),
      string.format("%.2f", self.sys_stat.cpu.average[2] * 100),
    })
  end
  if #self.sys_stat.cpu.average > 2 then
    -- Need localization
    self:put({
      _("  15 minutes usage %"),
      string.format("%.2f", self.sys_stat.cpu.average[3] * 100),
    })
  end
  -- Need localization
  self:put({
    _("  Usage % since boot"),
    string.format(
      "%.2f",
      (1 - self.sys_stat.cpu.idle / self.sys_stat.cpu.total) * 100
    ),
  })
  self:put({
    _("  Total memory (MB)"),
    string.format("%.2f", self.sys_stat.memory.total / 1024),
  })
  self:put({
    _("  Free memory (MB)"),
    string.format("%.2f", self.sys_stat.memory.free / 1024),
  })
  self:put({
    _("  Available memory (MB)"),
    string.format("%.2f", self.sys_stat.memory.available / 1024),
  })
end

function SystemStat:appendProcessInfo()
  local stat = io.open("/proc/self/stat", "r")
  assert(stat ~= nil)

  local t = util.splitToArray(stat:read("*line"), " ")
  stat:close()

  local n1, n2

  if #t == 0 then
    return
  end
  self:put({ _("Process"), "" })

  self:put({ _("  ID"), t[1] })

  if #t < 14 then
    return
  end
  n1 = tonumber(t[14])
  n2 = tonumber(t[15])
  if n1 ~= nil then
    if n2 ~= nil then
      n1 = n1 + n2
    end
    -- Need localization
    -- Fairly hard for reader.lua to use so much processor resources, do not
    -- change the unit to millions.
    self:put({ _("  Total ticks"), n1 })
    if self.sys_stat.cpu ~= nil and self.sys_stat.cpu.total ~= nil then
      assert(self.sys_stat.cpu.total > 0) -- Imporssible to be 0.
      self:put({
        _("  Processor usage %"),
        string.format("%.2f", n1 / self.sys_stat.cpu.total * 100),
      })
    end
  end

  if #t < 19 then
    return
  end
  -- Need localization
  self:put({ _("  Priority / nice"), t[18] .. " / " .. t[19] })

  if #t < 20 then
    return
  end
  n1 = tonumber(t[20])
  if n1 ~= nil then
    self:put({ _("  Threads"), tostring(n1) })
  end

  if #t < 23 then
    return
  end
  n1 = tonumber(t[23])
  if n1 ~= nil then
    self:put({
      _("  Virtual memory (MB)"),
      string.format("%.2f", n1 / 1024 / 1024),
    })
  end

  if #t < 24 then
    return
  end
  n1 = tonumber(t[24])
  if n1 ~= nil then
    self:put({ _("  RAM usage (MB)"), string.format("%.2f", n1 / 256) })
  end
end

function SystemStat:appendStorageInfo()
  if self.storage_filter == nil then
    return
  end

  local std_out = io.popen(
    "df -h | sed -r 's/ +/ /g' | grep "
      .. self.storage_filter
      .. " | sed 's/ /\\t/g' | cut -f 2,4,5,6"
  )
  assert(std_out ~= nil)

  self:put({ _("Storage information"), "" })
  for line in std_out:lines() do
    local t = util.splitToArray(line, "\t")
    if #t ~= 4 then
      self:put({ _("  Unexpected"), line })
    else
      self:put({ _("  Mount point"), t[4] })
      self:put({ _("  Available"), t[2] })
      self:put({ _("  Total"), t[1] })
      self:put({ _("  Used percentage"), t[3] })
    end
  end
  std_out:close()
end

function SystemStat:onSuspend()
  self.suspend_time = time.realtime()
  self.sleep_count = self.sleep_count + 1
end

function SystemStat:onResume()
  self.resume_time = time.realtime()
  self.wakeup_count = self.wakeup_count + 1
end

function SystemStat:onCharging()
  self.charge_count = self.charge_count + 1
end

function SystemStat:onNotCharging()
  self.discharge_count = self.discharge_count + 1
end

function SystemStat:showStatistics()
  self.kv_pairs = {}
  self.sys_stat = systemInfo()
  self:appendCounters()
  self:putSeparator()
  self:appendProcessInfo()
  self:putSeparator()
  self:appendStorageInfo()
  self:putSeparator()
  self:appendSystemInfo()
  UIManager:show(KeyValuePage:new({
    title = _("System statistics"),
    kv_pairs = self.kv_pairs,
  }))
end

SystemStat:init()

local SystemStatWidget = WidgetContainer:extend({
  name = "systemstat",
})

function SystemStatWidget:onDispatcherRegisterActions()
  Dispatcher:registerAction("system_statistics", {
    category = "none",
    event = "ShowSysStatistics",
    title = _("System statistics"),
    device = true,
    separator = true,
  })
end

function SystemStatWidget:init()
  self:onDispatcherRegisterActions()
  self.ui.menu:registerToMainMenu(self)
end

function SystemStatWidget:addToMainMenu(menu_items)
  menu_items.system_statistics = {
    text = _("System statistics"),
    keep_menu_open = true,
    callback = function()
      SystemStat:showStatistics()
    end,
  }
end

function SystemStatWidget:onShowSysStatistics()
  SystemStat:showStatistics()
end

function SystemStatWidget:onSuspend()
  SystemStat:onSuspend()
end

function SystemStatWidget:onResume()
  SystemStat:onResume()
end

function SystemStatWidget:onCharging()
  SystemStat:onCharging()
end

function SystemStatWidget:onNotCharging()
  SystemStat:onNotCharging()
end

return SystemStatWidget
