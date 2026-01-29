local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local powerd = Device:getPowerDevice()
local _ = require("gettext")
local C_ = _.pgettext
local T = require("ffi/util").template

battery_status_dismissed = false
battery_confirm_box = nil
memory_confirm_box = nil

local ReaderDeviceStatus = WidgetContainer:extend({})

function ReaderDeviceStatus:init()
  if not Device:hasBattery() and Device:isAndroid() then
    return
  end

  if Device:hasBattery() then
    self.battery_threshold = G_reader_settings:read("device_status_battery_threshold") or 20
    self.battery_threshold_high = G_reader_settings:read("device_status_battery_threshold_high") or 95
  end

  if not Device:isAndroid() then
    self.memory_threshold = G_reader_settings:read("device_status_memory_threshold") or 100
  end

  self.ui.menu:registerToMainMenu(self)
end

function ReaderDeviceStatus:_checkBatteryStatus()
  if battery_confirm_box then
    UIManager:close(battery_confirm_box)
    battery_confirm_box = nil
  end

  local is_charging = powerd:isCharging()
  local battery_capacity = powerd:getCapacity()
  if Device:canSuspend() and not is_charging and battery_capacity <= 5 then
    UIManager:show(InfoMessage:new({
      -- Need localization
      text = _("Battery level drops below the critical zone.\n\nSuspending the device…") .. "\n\n" .. _(
        "Waiting for 3 seconds to proceed."
      ),
      icon = "notice-warning",
      timeout = 3,
    }))
    UIManager:scheduleIn(3, function()
      UIManager:suspend()
    end)
    return
  end

  if battery_status_dismissed == true then -- alerts dismissed
    if
      (is_charging and battery_capacity <= self.battery_threshold_high)
      or (not is_charging and battery_capacity > self.battery_threshold)
    then
      battery_status_dismissed = false
    end
    return
  end
  if
    not (
      (is_charging and battery_capacity > self.battery_threshold_high)
      or (not is_charging and battery_capacity <= self.battery_threshold)
    )
  then
    return
  end

  local text
  if is_charging then
    assert(battery_capacity > self.battery_threshold_high)
    text = T(_("High battery level: %1 %\n\nDismiss battery level alert?"), battery_capacity)
  else
    assert(not is_charging and battery_capacity <= self.battery_threshold)
    text = T(_("Low battery level: %1 %\n\nDismiss battery level alert?"), battery_capacity)
    if Device:canSuspend() then
      text = text
        .. "\n\n"
        -- Need localization
        .. _(
          "When battery level drops below the critical zone, "
            .. "the device will be put into suspension automatically."
        )
    end
  end
  battery_confirm_box = ConfirmBox:new({
    text = text,
    ok_text = _("Dismiss"),
    dismissable = false,
    ok_callback = function()
      battery_status_dismissed = true
    end,
  })
  UIManager:show(battery_confirm_box)
end

function ReaderDeviceStatus:_checkMemoryStatus()
  local statm = io.open("/proc/self/statm", "r")
  if not statm then
    return
  end
  local dummy, rss = statm:read("*number", "*number")
  statm:close()
  rss = math.floor(rss * (4096 / 1024 / 1024))
  if rss < self.memory_threshold then
    return
  end
  if memory_confirm_box then
    UIManager:close(memory_confirm_box)
    memory_confirm_box = nil
  end
  if Device:canRestart() then
    local top_wg = UIManager:getTopmostVisibleWidget() or {}
    if top_wg.name == "ReaderUI" and G_reader_settings:isTrue("device_status_memory_auto_restart") then
      UIManager:show(InfoMessage:new({
        text = _("High memory usage!\n\nKOReader is restarting…")
          .. "\n\n"
          -- Need localization
          .. _("Waiting for 3 seconds to proceed."),
        icon = "notice-warning",
      }))
      UIManager:scheduleIn(3, function()
        UIManager:broadcastEvent(Event:new("Restart"))
      end)
    else
      memory_confirm_box = ConfirmBox:new({
        text = T(_("High memory usage: %1 MB\n\nRestart KOReader?"), rss),
        ok_text = _("Restart"),
        dismissable = false,
        ok_callback = function()
          UIManager:show(InfoMessage:new({
            text = _("High memory usage!\n\nKOReader is restarting…"),
            icon = "notice-warning",
          }))
          UIManager:nextTick(function()
            UIManager:broadcastEvent(Event:new("Restart"))
          end)
        end,
      })
      UIManager:show(memory_confirm_box)
    end
  else
    memory_confirm_box = ConfirmBox:new({
      text = T(_("High memory usage: %1 MB\n\nExit KOReader?"), rss),
      ok_text = _("Exit"),
      dismissable = false,
      ok_callback = function()
        UIManager:broadcastEvent("ExitKOReader")
      end,
    })
    UIManager:show(memory_confirm_box)
  end
end

function ReaderDeviceStatus:onTimesChange_5M()
  -- Sanity check.
  if Device:hasBattery() and G_reader_settings:isTrue("device_status_battery_alarm") then
    self:_checkBatteryStatus()
  end
  if not Device:isAndroid() and G_reader_settings:isTrue("device_status_memory_alarm") then
    self:_checkMemoryStatus()
  end
end

function ReaderDeviceStatus:addToMainMenu(menu_items)
  if not Device:hasBattery() and Device:isAndroid() then
    return
  end

  menu_items.device_status_alarm = {
    text = _("Device status alerts"),
    sub_item_table = {},
  }

  if Device:hasBattery() then
    table.insert(menu_items.device_status_alarm.sub_item_table, {
      text = _("Battery level"),
      checked_func = function()
        return G_reader_settings:isTrue("device_status_battery_alarm")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("device_status_battery_alarm")
      end,
    })
    table.insert(menu_items.device_status_alarm.sub_item_table, {
      text_func = function()
        return T(_("Thresholds: %1 % / %2 %"), self.battery_threshold, self.battery_threshold_high)
      end,
      enabled_func = function()
        return G_reader_settings:isTrue("device_status_battery_alarm")
      end,
      keep_menu_open = true,
      callback = function(touchmenu_instance)
        local DoubleSpinWidget = require("/ui/widget/doublespinwidget")
        local thresholds_widget
        thresholds_widget = DoubleSpinWidget:new({
          title_text = _("Battery level alert thresholds"),
          info_text = _([[
Low level threshold is checked when the device is not charging.
High level threshold is checked when the device is charging.]]),
          left_text = _("Low"),
          left_value = self.battery_threshold,
          left_min = 10,
          left_max = math.min(self.battery_threshold_high, 40),
          left_hold_step = 5,
          right_text = _("High"),
          right_value = self.battery_threshold_high,
          right_min = math.max(self.battery_threshold, 60),
          right_max = 100,
          right_hold_step = 5,
          unit = "%",
          callback = function(left_value, right_value)
            self.battery_threshold = left_value
            self.battery_threshold_high = right_value
            assert(self.battery_threshold < self.battery_threshold_high)
            G_reader_settings:save("device_status_battery_threshold", self.battery_threshold, 20)
            G_reader_settings:save("device_status_battery_threshold_high", self.battery_threshold_high, 95)
            touchmenu_instance:updateItems()
            battery_status_dismissed = false
          end,
        })
        UIManager:show(thresholds_widget)
      end,
      separator = true,
    })
  end
  if not Device:isAndroid() then
    table.insert(menu_items.device_status_alarm.sub_item_table, {
      text = _("High memory usage"),
      checked_func = function()
        return G_reader_settings:isTrue("device_status_memory_alarm")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("device_status_memory_alarm")
      end,
    })
    table.insert(menu_items.device_status_alarm.sub_item_table, {
      text_func = function()
        return T(_("Threshold: %1 MB"), self.memory_threshold)
      end,
      enabled_func = function()
        return G_reader_settings:isTrue("device_status_memory_alarm")
      end,
      keep_menu_open = true,
      callback = function(touchmenu_instance)
        UIManager:show(SpinWidget:new({
          value = self.memory_threshold,
          value_min = 20,
          value_max = 500,
          unit = C_("Data storage size", "MB"),
          value_step = 5,
          value_hold_step = 10,
          title_text = _("Memory alert threshold"),
          callback = function(spin)
            self.memory_threshold = spin.value
            G_reader_settings:save("device_status_memory_threshold", self.memory_threshold)
            touchmenu_instance:updateItems()
          end,
        }))
      end,
    })
    table.insert(menu_items.device_status_alarm.sub_item_table, {
      text = _("Automatic restart"),
      enabled_func = function()
        return G_reader_settings:isTrue("device_status_memory_alarm") and Device:canRestart()
      end,
      checked_func = function()
        return G_reader_settings:isTrue("device_status_memory_auto_restart")
      end,
      callback = function()
        G_reader_settings:flipNilOrFalse("device_status_memory_auto_restart")
      end,
    })
  end
end

return ReaderDeviceStatus
