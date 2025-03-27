--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.autodim
--]]--

local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
local Device = require("device")
local PluginShare = require("pluginshare")
local SpinWidget = require("ui/widget/spinwidget")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local time = require("ui/time")
local _ = require("gettext")
local C_ = _.pgettext
local Powerd = Device.powerd
local T = require("ffi/util").template

local DEFAULT_AUTODIM_DURATION_S = 5
local DEFAULT_AUTODIM_FRACTION = 20

local AutoDim = WidgetContainer:extend{
  name = "autodim",
  -- Copied from SwitchPlugin.
  settings_id = math.floor(os.clock() * 1000),
  -- For BackgroundTaskPlugin
  enabled = true,
  -- Check once per 10 seconds, it's less critical.
  when = 10,
}

function AutoDim:init()
  self.autodim_starttime_m =
      G_reader_settings:readSetting("autodim_starttime_minutes") or -1
  self.autodim_duration_s =
      G_reader_settings:readSetting("autodim_duration_seconds") or DEFAULT_AUTODIM_DURATION_S
  self.autodim_fraction =
      G_reader_settings:readSetting("autodim_fraction") or DEFAULT_AUTODIM_FRACTION

  self.ui.menu:registerToMainMenu(self)

  -- For BackgroundTaskPlugin
  self.executable = function() self:_executable() end

  self:_scheduleAutoDimTask()
end

function AutoDim:addToMainMenu(menu_items)
  menu_items.autodim = {
    text = _("Automatic dimmer"),
    checked_func = function() return self.autodim_starttime_m > 0 end,
    sub_item_table = {
      {
        text_func = function()
          return self.autodim_starttime_m <= 0 and
                 _("Idle time for dimmer") or
                 T(_("Idle time for dimmer: %1"),
                     datetime.secondsToClockDuration("letters",
                                                     self.autodim_starttime_m * 60,
                                                     false,
                                                     false,
                                                     true))
        end,
        checked_func = function() return self.autodim_starttime_m > 0 end,
        callback = function(menu)
          local idle_dialog = SpinWidget:new{
            title_text = _("Automatic dimmer idle time"),
            info_text = _("Start the dimmer after the designated period of inactivity."),
            value = self.autodim_starttime_m >= 0 and self.autodim_starttime_m or 0.5,
            default_value = Device:isKindle() and 4 or 5,
            value_min = 0.5,
            value_max = 60,
            value_step = 0.5,
            value_hold_step = 5,
            unit = C_("Time", "min"),
            precision = "%0.1f",
            ok_always_enabled = true,
            callback = function(spin)
              if not spin then return end
              self.autodim_starttime_m = spin.value
              G_reader_settings:saveSetting("autodim_starttime_minutes", spin.value)
              self:_scheduleAutoDimTask()
              menu:updateItems()
            end,
            extra_text = _("Disable"),
            extra_callback = function()
              self.autodim_starttime_m = -1
              G_reader_settings:saveSetting("autodim_starttime_minutes", -1)
              self:_scheduleAutoDimTask()
              menu:updateItems()
            end,
          }
          UIManager:show(idle_dialog)
        end,
        keep_menu_open = true,
      },
      {
        text_func = function()
          return T(_("Dimmer duration: %1"),
                   datetime.secondsToClockDuration("letters",
                                                   self.autodim_duration_s,
                                                   false,
                                                   false,
                                                   true))
        end,
        enabled_func = function() return self.autodim_starttime_m > 0 end,
        callback = function(menu)
          local dimmer_dialog = SpinWidget:new{
            title_text = _("Automatic dimmer duration"),
            info_text = _("Delay to reach the lowest brightness."),
            value = self.autodim_duration_s,
            default_value = DEFAULT_AUTODIM_DURATION_S,
            value_min = 0,
            value_max = 300,
            value_step = 1,
            value_hold_step = 10,
            precision = "%1d",
            unit = C_("Time", "s"),
            callback = function(spin)
              if not spin then return end
              self.autodim_duration_s = spin.value
              G_reader_settings:saveSetting("autodim_duration_seconds", spin.value)
              self:_scheduleAutoDimTask()
              menu:updateItems()
            end,
          }
          UIManager:show(dimmer_dialog)
        end,
        keep_menu_open = true,
      },
      {
        text_func = function()
          return T(_("Dim to %1 % of the regular brightness"), self.autodim_fraction)
        end,
        enabled_func = function() return self.autodim_starttime_m > 0 end,
        callback = function(menu)
          local percentage_dialog = SpinWidget:new{
            title_text = _("Dim to percentage"),
            info_text = _("The lowest brightness as a percentage of the regular brightness."),
            value = self.autodim_fraction,
            value_default = DEFAULT_AUTODIM_FRACTION,
            value_min = 0,
            value_max = 100,
            value_hold_step = 10,
            unit = "%",
            callback = function(spin)
              self.autodim_fraction = spin.value
              G_reader_settings:saveSetting("autodim_fraction", spin.value)
              self:_scheduleAutoDimTask()
              menu:updateItems()
            end,
          }
          UIManager:show(percentage_dialog)
        end,
        keep_menu_open = true,
      },
    }
  }
end

function AutoDim:_scheduleAutoDimTask()
  self.settings_id = self.settings_id + 1
  -- Technically speaking, it's possible to start the autodim
  -- "as soon as possible".
  if self.autodim_starttime_m >= 0 then
    -- A slightly hacky, but very lua way of running the task.
    BackgroundTaskPlugin._start(self)
  end
end

function AutoDim:_restoreFrontlight()
  if self.origin_fl then
    Powerd:setIntensity(self.origin_fl)
    self.origin_fl = nil
  end
end

-- Do not use onSuspend, it may not work on kindle since koreader cannot
-- reliably receive the suspend signal.
function AutoDim:onResume()
  if not self.trap_widget then return end
  -- But ensure the self.trap_widget flag can be posted to the ramp down
  -- task.
  local trap_widget = self.trap_widget
  self.trap_widget = nil
  UIManager:nextTick(function()
    self:_clearIdling()
    self:_restoreFrontlight()
    UIManager:close(trap_widget)
  end)
end

function AutoDim:_clearIdling()
  PluginShare.DeviceIdling = nil
end

function AutoDim:onClose()
  BackgroundTaskPlugin.onClose(self)
end

function AutoDim:onCloseWidget()
  BackgroundTaskPlugin.onCloseWidget(self)
end

function AutoDim:onFrontlightTurnedOff()
  -- This might be happening through autowarmth during a ramp down.
  if not self.trap_widget then return end
  -- Set original intensity, but don't turn fl on actually.
  Powerd.fl_intensity = self.origin_fl or Powerd.fl_intensity
  self.origin_fl = nil
  if self.trap_widget then
    self:_clearIdling()
    UIManager:close(self.trap_widget) -- don't swallow input events from now
    self.trap_widget = nil
  end
end

function AutoDim:_shouldNotDim()
  return UIManager:timeSinceLastUserAction() < time.s(self.autodim_starttime_m * 60)
end

function AutoDim:_executable()
  if self.trap_widget then return end -- already dimmed.
  if self:_shouldNotDim() then return end
  -- Do not ramp down if the frontlight is off.
  if Powerd:isFrontlightOff() then return end

  self.origin_fl = self.origin_fl or Powerd:frontlightIntensity()
  local autodim_end_fl = math.floor(self.origin_fl * self.autodim_fraction * (1/100) + 0.5)
  -- Clamp `autodim_end_fl` to 1 if `self.autodim_fraction` ~= 0
  if self.autodim_fraction ~= 0 and autodim_end_fl == 0 then
    autodim_end_fl = 1
  end
  local fl_diff = self.origin_fl - autodim_end_fl
  if fl_diff <= 0 then
    -- Well, this is likely impossible, but in case the combination of the
    -- configurations is weird.
    self.origin_fl = nil
    return
  end

  -- Start ramp down
  assert(not self.trap_widget)
  self.trap_widget = TrapWidget:new{
    name = "AutoDim",
    dismiss_callback = function()
      self:_clearIdling()
      self:_restoreFrontlight()
      self.trap_widget = nil
    end
  }
  UIManager:show(self.trap_widget) -- suppress taps during dimming
  PluginShare.DeviceIdling = true

  -- BackgroundTaskRunner isn't designed to run rapid jobs.
  self:_rampTask(fl_diff, autodim_end_fl, math.max(self.autodim_duration_s / fl_diff, 0.001))
end

function AutoDim:_rampTask(fl_diff, autodim_end_fl, delay)
  -- Something else happened, like resumed, stopping the ramp down.
  if not self.trap_widget then return end
  -- User actions, likely won't happen, but in case the user action was
  -- triggered by not dismissing the TrapWidget.
  if self:_shouldNotDim() then return end
  local fl_level = Powerd:frontlightIntensity()
  -- Well, something else may happened as well, e.g. some other logic changed
  -- the frontlight level.
  if fl_level <= autodim_end_fl then return end
  fl_level = fl_level - 1
  Powerd:setIntensity(fl_level)
  -- Reduce the frequency of firing frontlight level change event on
  -- eink devices.
  if not Device:hasEinkScreen() or ((self.origin_fl - fl_level) % 2 == 0) then
    UIManager:broadcastEvent("UpdateFooter")
  end
  if fl_level > autodim_end_fl then
    UIManager:scheduleIn(delay, AutoDim._rampTask, self, fl_diff, autodim_end_fl, delay)
  end
end

return AutoDim
