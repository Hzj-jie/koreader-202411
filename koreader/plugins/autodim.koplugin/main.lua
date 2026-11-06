--[[--
Plugin for automatic dimming of the frontlight after an idle period.

@module koplugin.autodim
--]]
--

local Device = require("device")
local SpinWidget = require("ui/widget/spinwidget")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local gettext = require("gettext")
local C_ = gettext.pgettext
local Powerd = Device.powerd
local T = require("ffi/util").template

-- Instead of embedding these constants, keep them here so that if there is
-- really a need of changing them, e.g. from G_defaults, the change would be
-- easier.
local AUTODIM_DURATION_S = 1
local AUTODIM_END_FL = 1
-- Avoid caching the common _meta.lua file name as a module.
local HELP_TEXT = require("plugins/autodim.koplugin/_meta").description

local AutoDim = WidgetContainer:extend({
  name = "autodim",
})

function AutoDim:init()
  self.autodim_starttime_m = G_named_settings.autodim_starttime_minutes()

  self.ui.menu:registerToMainMenu(self)
end

function AutoDim:addToMainMenu(menu_items)
  menu_items.autodim = {
    text_func = function()
      return gettext("Automatic dimmer")
        .. ": "
        .. (
          self.autodim_starttime_m <= 0 and gettext("disabled")
          or T(
            gettext("after %1"),
            datetime.secondsToClockDuration(
              "letters",
              self.autodim_starttime_m * 60,
              false,
              false,
              true
            )
          )
        )
    end,
    checked_func = function()
      return self.autodim_starttime_m > 0
    end,
    callback = function(menu)
      local idle_dialog = SpinWidget:new({
        title_text = gettext("Automatic dimmer idle time"),
        info_text = gettext(
          "Start the dimmer after the designated period of inactivity."
        ),
        value = self.autodim_starttime_m >= 0 and self.autodim_starttime_m
          or G_named_settings.default.autodim_starttime_minutes(),
        default_value = G_named_settings.default.autodim_starttime_minutes(),
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
          G_named_settings.set.autodim_starttime_minutes(spin.value)
          menu:updateItems()
        end,
        extra_text = gettext("Disable"),
        extra_callback = function()
          self.autodim_starttime_m = -1
          G_named_settings.set.autodim_starttime_minutes(-1)
          menu:updateItems()
        end,
      })
      UIManager:show(idle_dialog)
    end,
    keep_menu_open = true,
    help_text = HELP_TEXT,
  }
end

function AutoDim:_restoreFrontlight()
  if self.origin_fl then
    Powerd:setIntensity(self.origin_fl)
    self.origin_fl = nil
  end
end

function AutoDim:onDeviceIdling()
  if self.trap_widget or self.autodim_starttime_m <= 0 or Powerd:isFrontlightOff() then
    return
  end

  self.origin_fl = self.origin_fl or Powerd:frontlightIntensity()
  local fl_diff = self.origin_fl - AUTODIM_END_FL
  if fl_diff <= 0 then
    self.origin_fl = nil
    return
  end

  self.trap_widget = TrapWidget:new({
    name = "AutoDim",
    dismiss_callback = function()
      self:_restoreFrontlight()
      self.trap_widget = nil
    end,
  })
  UIManager:show(self.trap_widget)
  UIManager:unschedule(AutoDim._rampTask)
  self:_rampTask(fl_diff, math.max(AUTODIM_DURATION_S / fl_diff, 0.001))
end

function AutoDim:onDeviceBusy()
  UIManager:unschedule(AutoDim._rampTask)
end

function AutoDim:onResume()
  if not self.trap_widget then
    return
  end
  local trap_widget = self.trap_widget
  self.trap_widget = nil
  UIManager:nextTick(function()
    self:_restoreFrontlight()
    UIManager:close(trap_widget)
  end)
end

function AutoDim:onClose()
  UIManager:unschedule(AutoDim._rampTask)
  self:_restoreFrontlight()
  if self.trap_widget then
    UIManager:closeIfShown(self.trap_widget)
    self.trap_widget = nil
  end
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
    UIManager:close(self.trap_widget) -- don't swallow input events from now
    self.trap_widget = nil
  end
end

function AutoDim:_rampTask(fl_diff, delay)
  -- Something else happened, like resumed, stopping the ramp down.
  if not self.trap_widget then
    return
  end
  -- Stops the ramp down when the device is suspending.
  if Device.screen_saver_mode then
    return
  end
  local fl_level = Powerd:frontlightIntensity()
  if fl_level <= AUTODIM_END_FL then
    if Device:hasEinkScreen() then
      UIManager:broadcastEvent("UpdateFooter")
    end
    return
  end
  fl_level = fl_level - 1
  Powerd:setIntensity(fl_level)
  if not Device:hasEinkScreen() then
    UIManager:broadcastEvent("UpdateFooter")
  end
  if fl_level > AUTODIM_END_FL then
    UIManager:scheduleIn(delay, AutoDim._rampTask, self, fl_diff, delay)
  end
end

return AutoDim
