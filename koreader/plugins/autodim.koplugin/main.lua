--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.autodim
--]]
--

local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
local Device = require("device")
local PluginShare = require("pluginshare")
local SpinWidget = require("ui/widget/spinwidget")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local time = require("ui/time")
local gettext = require("gettext")
local C_ = gettext.pgettext
local Powerd = Device.powerd
local T = require("ffi/util").template

-- Instead of embedding these constants, keep them here so that if there is
-- really a need of changing them, e.g. from G_defaults, the change would be
-- easier.
local AUTODIM_DURATION_S = 1
local AUTODIM_END_FL = 1
-- Kindle auto-shuts off in roughly 10 minutes, cut it into half.
local DEFAULT_AUTODIM_STARTTIME_M = 5
-- Avoid caching the common _meta.lua file name as a module.
local HELP_TEXT = dofile("plugins/autodim.koplugin/_meta.lua").description

local AutoDim = WidgetContainer:extend({
  name = "autodim",
  -- Copied from SwitchPlugin.
  settings_id = math.floor(os.clock() * 1000),
  -- For BackgroundTaskPlugin
  enabled = true,
  -- Check once per 10 seconds, it's less critical.
  when = 10,
})

function AutoDim:init()
  self.autodim_starttime_m = G_reader_settings:read("autodim_starttime_minutes") or -1

  self.ui.menu:registerToMainMenu(self)

  -- For BackgroundTaskPlugin
  self.executable = function()
    self:_executable()
  end

  self:_scheduleAutoDimTask()
end

function AutoDim:addToMainMenu(menu_items)
  menu_items.autodim = {
    text_func = function()
      return gettext("Automatic dimmer")
        .. ": "
        -- Need localization.
        .. (
          self.autodim_starttime_m <= 0 and gettext("disabled")
          or T(
            gettext("after %1"),
            datetime.secondsToClockDuration("letters", self.autodim_starttime_m * 60, false, false, true)
          )
        )
    end,
    checked_func = function()
      return self.autodim_starttime_m > 0
    end,
    callback = function(menu)
      local idle_dialog = SpinWidget:new({
        title_text = gettext("Automatic dimmer idle time"),
        info_text = gettext("Start the dimmer after the designated period of inactivity."),
        value = self.autodim_starttime_m >= 0 and self.autodim_starttime_m or DEFAULT_AUTODIM_STARTTIME_M,
        default_value = DEFAULT_AUTODIM_STARTTIME_M,
        value_min = 0.5,
        -- kindle auto-shuts off in roughly 10 minutes.
        value_max = Device:isKindle() and 8 or 60,
        value_step = 0.5,
        value_hold_step = 5,
        unit = C_("Time", "min"),
        precision = "%0.1f",
        ok_always_enabled = true,
        callback = function(spin)
          if not spin then
            return
          end
          self.autodim_starttime_m = spin.value
          G_reader_settings:save("autodim_starttime_minutes", spin.value)
          self:_scheduleAutoDimTask()
          menu:updateItems()
        end,
        extra_text = gettext("Disable"),
        extra_callback = function()
          self.autodim_starttime_m = -1
          G_reader_settings:save("autodim_starttime_minutes", -1)
          self:_scheduleAutoDimTask()
          menu:updateItems()
        end,
      })
      UIManager:show(idle_dialog)
    end,
    keep_menu_open = true,
    help_text = HELP_TEXT,
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

function AutoDim:onResume()
  if not self.trap_widget then
    return
  end
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
  PluginShare.DeviceIdling = false
end

function AutoDim:onExit()
  BackgroundTaskPlugin.onExit(self)
end

function AutoDim:onClose()
  BackgroundTaskPlugin.onClose(self)
end

function AutoDim:onFrontlightTurnedOff()
  -- This might be happening through autowarmth during a ramp down.
  if not self.trap_widget then
    return
  end
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
  if self.trap_widget then
    return
  end -- already dimmed.
  if self:_shouldNotDim() then
    return
  end
  -- Do not ramp down if the frontlight is off.
  if Powerd:isFrontlightOff() then
    return
  end

  self.origin_fl = self.origin_fl or Powerd:frontlightIntensity()
  local fl_diff = self.origin_fl - AUTODIM_END_FL
  if fl_diff <= 0 then
    -- Well, this is likely impossible, but in case the combination of the
    -- configurations is weird.
    self.origin_fl = nil
    return
  end

  -- Start ramp down
  assert(not self.trap_widget)
  self.trap_widget = TrapWidget:new({
    name = "AutoDim",
    dismiss_callback = function()
      self:_clearIdling()
      self:_restoreFrontlight()
      self.trap_widget = nil
    end,
  })
  UIManager:show(self.trap_widget) -- suppress taps during dimming
  PluginShare.DeviceIdling = true

  -- BackgroundTaskRunner isn't designed to run rapid jobs.
  UIManager:unschedule(AutoDim._rampTask)
  self:_rampTask(fl_diff, math.max(AUTODIM_DURATION_S / fl_diff, 0.001))
end

function AutoDim:_rampTask(fl_diff, delay)
  -- Something else happened, like resumed, stopping the ramp down.
  if not self.trap_widget then
    return
  end
  -- Stops the ramp down when the device is suspending. This condition likely
  -- shouldn't be triggered, since the UIManager would stop running tasks, but
  -- in case the _rampTask is happening during the onSuspend procedure.
  if Device.screen_saver_mode then
    return
  end
  -- User actions, likely won't happen, but in case the user action was
  -- triggered by not dismissing the TrapWidget.
  if self:_shouldNotDim() then
    return
  end
  local fl_level = Powerd:frontlightIntensity()
  -- Well, something else may happened as well, e.g. some other logic changed
  -- the frontlight level.
  if fl_level <= AUTODIM_END_FL then
    if Device:hasEinkScreen() then
      UIManager:broadcastEvent("UpdateFooter")
    end
    return
  end
  fl_level = fl_level - 1
  Powerd:setIntensity(fl_level)
  -- Reduce the frequency of firing frontlight level change event on
  -- eink devices.
  if not Device:hasEinkScreen() then
    UIManager:broadcastEvent("UpdateFooter")
  end
  if fl_level > AUTODIM_END_FL then
    UIManager:scheduleIn(delay, AutoDim._rampTask, self, fl_diff, delay)
  end
end

return AutoDim
