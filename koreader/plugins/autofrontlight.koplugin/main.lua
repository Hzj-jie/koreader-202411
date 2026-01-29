local Device = require("device")

if not (Device.isEmulator() or (Device:isKindle() and Device:hasLightSensor())) then
  return { disabled = true }
end

local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
local PluginShare = require("pluginshare")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoFrontlightPlugin = BackgroundTaskPlugin:extend()

function AutoFrontlightPlugin:new(o)
  o = o or {}
  o.name = "autofrontlight"
  o.default_enable = true
  o.when = "asap"
  o.last_brightness = -1
  o.executable = function()
    AutoFrontlightPlugin._action(o)
  end
  o.menu_item = "auto_frontlight"
  o.menu_text = _("Auto frontlight")
  o.full_confirm_message = function()
    return T(
      _(
        "Auto frontlight detects the brightness of the environment and automatically turn on and off the frontlight.\nFrontlight will be turned off to save battery in bright environment, and turned on in dark environment.\nDo you want to %1 it?"
      ),
      o.enabled and _("disable") or _("enable")
    )
  end
  return BackgroundTaskPlugin.new(self, o)
end

function AutoFrontlightPlugin:_action()
  if PluginShare.DeviceIdling == true then
    return
  end
  local current_level = Device:ambientBrightnessLevel()
  logger.dbg("AutoFrontlight:_action(): Retrieved ambient brightness level: ", current_level)
  if self.last_brightness == current_level then
    logger.dbg("AutoFrontlight:_action(): recorded brightness is same as current level ", self.last_brightness)
    return
  end
  if current_level <= 1 then
    logger.dbg("AutoFrontlight: going to turn on frontlight")
    Device:getPowerDevice():turnOnFrontlight()
  elseif current_level >= 3 then
    logger.dbg("AutoFrontlight: going to turn off frontlight")
    Device:getPowerDevice():turnOffFrontlight()
  end
  self.last_brightness = current_level
end

return AutoFrontlightPlugin
