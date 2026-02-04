local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local C_ = gettext.pgettext
local T = require("ffi/util").template

-- This affects the topmenu, we want to be able to access it even if !Device:setDateTime()
local menu = {
  text = gettext("Time and date"),
  sub_item_table = {
    {
      text = gettext("12-hour clock"),
      keep_menu_open = true,
      checked_func = function()
        return G_reader_settings:isTrue("twelve_hour_clock")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("twelve_hour_clock")
        UIManager:broadcastEvent("TimeFormatChanged")
      end,
    },
    {
      text_func = function()
        local duration_format = G_named_settings.duration_format()
        local text = C_("Time", "Classic")
        if duration_format == "modern" then
          text = C_("Time", "Modern")
        elseif duration_format == "letters" then
          text = C_("Time", "Letters")
        end
        return T(gettext("Duration format: %1"), text)
      end,
      sub_item_table = {
        {
          text_func = function()
            local datetime = require("datetime")
            -- sample text shows 1:23:45
            local duration_format_str = datetime.secondsToClockDuration("classic", 5025, false)
            return T(C_("Time", "Classic (%1)"), duration_format_str)
          end,
          checked_func = function()
            return G_named_settings.duration_format() == "classic"
          end,
          callback = function()
            G_reader_settings:save("duration_format", "classic")
            UIManager:broadcastEvent("UpdateFooter")
          end,
        },
        {
          text_func = function()
            local datetime = require("datetime")
            -- sample text shows 1h23'45"
            local duration_format_str = datetime.secondsToClockDuration("modern", 5025, false)
            return T(C_("Time", "Modern (%1)"), duration_format_str)
          end,
          checked_func = function()
            return G_named_settings.duration_format() == "modern"
          end,
          callback = function()
            G_reader_settings:save("duration_format", "modern")
            UIManager:broadcastEvent("UpdateFooter")
          end,
        },
        {
          text_func = function()
            local datetime = require("datetime")
            -- sample text shows 1h 23m 45s
            local duration_format_str = datetime.secondsToClockDuration("letters", 5025, false)
            return T(C_("Time", "Letters (%1)"), duration_format_str)
          end,
          checked_func = function()
            return G_named_settings.duration_format() == "letters"
          end,
          callback = function()
            G_reader_settings:save("duration_format", "letters")
            UIManager:broadcastEvent("UpdateFooter")
          end,
        },
      },
    },
  },
}
if Device:setDateTime() then
  table.insert(menu.sub_item_table, {
    text = gettext("Set time"),
    keep_menu_open = true,
    callback = function()
      local now_t = os.date("*t")
      local curr_hour = now_t.hour
      local curr_min = now_t.min
      local time_widget = DateTimeWidget:new({
        hour = curr_hour,
        min = curr_min,
        ok_text = gettext("Set time"),
        title_text = gettext("Set time"),
        info_text = gettext("Time is in hours and minutes."),
        callback = function(time)
          if Device:setDateTime(nil, nil, nil, time.hour, time.min) then
            now_t = os.date("*t")
            UIManager:show(InfoMessage:new({
              text = T(
                gettext("Current time: %1:%2"),
                string.format("%02d", now_t.hour),
                string.format("%02d", now_t.min)
              ),
            }))
          else
            UIManager:show(InfoMessage:new({
              text = gettext("Time couldn't be set"),
            }))
          end
        end,
      })
      UIManager:show(time_widget)
    end,
  })
  table.insert(menu.sub_item_table, {
    text = gettext("Set date"),
    keep_menu_open = true,
    callback = function()
      local now_t = os.date("*t")
      local curr_year = now_t.year
      local curr_month = now_t.month
      local curr_day = now_t.day
      local date_widget = DateTimeWidget:new({
        year = curr_year,
        month = curr_month,
        day = curr_day,
        ok_text = gettext("Set date"),
        title_text = gettext("Set date"),
        info_text = gettext("Date is in years, months and days."),
        callback = function(time)
          now_t = os.date("*t")
          if Device:setDateTime(time.year, time.month, time.day, now_t.hour, now_t.min, now_t.sec) then
            now_t = os.date("*t")
            UIManager:show(InfoMessage:new({
              text = T(
                gettext("Current date: %1-%2-%3"),
                now_t.year,
                string.format("%02d", now_t.month),
                string.format("%02d", now_t.day)
              ),
            }))
          else
            UIManager:show(InfoMessage:new({
              text = gettext("Date couldn't be set"),
            }))
          end
        end,
      })
      UIManager:show(date_widget)
    end,
  })
end

local function add_sync_time()
  local lfs = require("libs/libkoreader-lfs")
  local ffi = require("ffi")
  local C = ffi.C
  require("ffi/posix_h")
  -- We need to be root to be able to set the time (CAP_SYS_TIME)
  if C.getuid() ~= 0 then
    return
  end

  local ntp_cmd
  -- Check if we have access to ntpd or ntpdate
  if os.execute("command -v ntpd >/dev/null") == 0 then
    -- Make sure it's actually busybox's implementation, as the syntax may otherwise differ...
    -- (Of particular note, Kobo ships busybox ntpd, but not ntpdate; and Kindle ships ntpdate and !busybox ntpd).
    local path = os.getenv("PATH") or ""
    for p in path:gmatch("([^:]+)") do
      local sym = lfs.symlinkattributes(p .. "/ntpd")
      if sym and sym.mode == "link" and string.sub(sym.target, -7) == "busybox" then
        ntp_cmd = "ntpd -q -n -p pool.ntp.org"
        break
      end
    end
  end
  if not ntp_cmd and os.execute("command -v ntpdate >/dev/null") == 0 then
    ntp_cmd = "ntpdate pool.ntp.org"
  end
  if not ntp_cmd then
    return
  end

  local NetworkMgr = require("ui/network/manager")

  local function currentTime()
    local std_out = io.popen("date")
    if std_out then
      local result = std_out:read("*line")
      std_out:close()
      if result ~= nil then
        return T(gettext("New time is %1."), result)
      end
    end
    return gettext("Time synchronized.")
  end

  local function syncNTPOnly()
    local txt
    if os.execute(ntp_cmd) ~= 0 then
      txt = gettext("Failed to retrieve time from server. Please check your network configuration.")
    else
      txt = currentTime()
      os.execute("hwclock -u -w")

      -- On Kindle, do it the native way, too, to make sure the native UI gets the memo...
      if Device:isKindle() and lfs.attributes("/usr/sbin/setdate", "mode") == "file" then
        os.execute(string.format("/usr/sbin/setdate '%d'", os.time()))
      end
    end
    return txt
  end

  local function syncNTP()
    local txt
    UIManager:runWith(function()
      txt = syncNTPOnly()
    end, gettext("Synchronizing time. This may take several seconds."))

    UIManager:show(InfoMessage:new({
      text = txt,
      timeout = 3,
    }))
  end

  table.insert(menu.sub_item_table, {
    text = gettext("Synchronize time"),
    keep_menu_open = true,
    callback = function()
      NetworkMgr:runWhenOnline(function()
        syncNTP()
      end)
    end,
  })
end

add_sync_time()

return menu
