local Device = require("device")

if Device:isKindle() then
  -- No obvious reason to enable to plugin on kindles since they do have
  -- auto suspend logic internally.
  return { disabled = true }
end

if not Device:canSuspend() then
  return { disabled = true }
end

local Math = require("optmath")
local PluginShare = require("pluginshare")
local PowerD = Device:getPowerDevice()
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local gettext = require("gettext")
local logger = require("logger")
local time = require("ui/time")
local T = require("ffi/util").template

local default_auto_suspend_timeout_seconds = 15 * 60 -- 15 minutes

local AutoSuspend = WidgetContainer:extend({
  name = "autosuspend",
  is_doc_only = false,
  auto_suspend_timeout_seconds = default_auto_suspend_timeout_seconds,
  task = nil,
})

function AutoSuspend:_enabled()
  -- NOTE: Plugin is only enabled if Device:canSuspend(), so we can elide the check here
  return self.auto_suspend_timeout_seconds > 0
end

function AutoSuspend:_schedule()
  if not self:_enabled() then
    logger.dbg("AutoSuspend: suspend timer is disabled")
    return
  end

  local suspend_delay_seconds
  local is_charging
  -- On devices with an auxiliary battery, we only care about the auxiliary battery being charged...
  if Device:hasAuxBattery() and PowerD:isAuxBatteryConnected() then
    is_charging = PowerD:isAuxCharging() and not PowerD:isAuxCharged()
  else
    is_charging = PowerD:isCharging() and not PowerD:isCharged()
  end
  -- We *do* want to make sure we attempt to go into suspend again while *fully* charged, though.
  if PluginShare.pause_auto_suspend or is_charging then
    suspend_delay_seconds = self.auto_suspend_timeout_seconds
  else
    local idle_time = UIManager:timeSinceLastUserAction()
    suspend_delay_seconds = self.auto_suspend_timeout_seconds
      - time.to_number(idle_time)
  end

  if suspend_delay_seconds <= 0 then
    logger.dbg("AutoSuspend: will suspend the device")
    UIManager:suspend()
  else
    logger.dbg(
      "AutoSuspend: scheduling next suspend check in",
      suspend_delay_seconds
    )
    UIManager:scheduleIn(suspend_delay_seconds, self.task)
  end
end

function AutoSuspend:_unschedule()
  if self.task then
    logger.dbg("AutoSuspend: unschedule suspend timer")
    UIManager:unschedule(self.task)
  end
end

function AutoSuspend:_start()
  if self:_enabled() then
    logger.dbg(
      "AutoSuspend: start suspend timer at",
      time.format_time(UIManager:lastUserActionTime())
    )
    self:_schedule()
  end
end

function AutoSuspend:init()
  logger.dbg("AutoSuspend: init")
  self.auto_suspend_timeout_seconds = G_reader_settings:read(
    "auto_suspend_timeout_seconds",
    default_auto_suspend_timeout_seconds
  )

  -- We need an instance-specific function reference to schedule, because in some rare cases,
  -- we may instantiate a new plugin instance *before* tearing down the old one.
  -- If we only cared about accessing the right instance members,
  -- we could use scheduleIn(t, self.function, self),
  -- but we also care about unscheduling the task from *this* instance only:
  -- unschedule(self.function) would unschedule that function for *every* instance,
  -- as self.function == AutoSuspend.function ;).
  self.task = function()
    self:_schedule()
  end

  self:_start()

  assert(self.ui ~= nil and self.ui.menu ~= nil)
  self.ui.menu:registerToMainMenu(self)
end

-- NOTE: event_hook takes care of overloading this to unregister the hook, too.
function AutoSuspend:onClose()
  logger.dbg("AutoSuspend: onClose")

  self:_unschedule()
  self.task = nil
end

function AutoSuspend:onSuspend()
  logger.dbg("AutoSuspend: onSuspend")
  -- We do not want auto suspend procedure to waste battery during suspend. So let's unschedule it
  -- when suspending and restart it after resume.
  self:_unschedule()
end

function AutoSuspend:onResume()
  logger.dbg("AutoSuspend: onResume")
  self:_unschedule()
  -- We should always follow an InputEvent, so last_action_time is already up to date :).
  self:_start()
end

function AutoSuspend:pickTimeoutValue(
  menu,
  title,
  info,
  setting,
  default_value,
  range
)
  local InfoMessage = require("ui/widget/infomessage")
  local DateTimeWidget = require("ui/widget/datetimewidget")

  local setting_val = self[setting] > 0 and self[setting] or default_value

  local time_spinner
  time_spinner = DateTimeWidget:new({
    hour = math.floor(setting_val * (1 / 3600)),
    min = math.floor(setting_val * (1 / 60)) % 60,
    hour_hold_step = 5,
    min_hold_step = 10,
    hour_max = math.floor(range[2] * (1 / 3600)) - 1,
    min_max = 59,
    ok_text = gettext("Set timeout"),
    title_text = title,
    info_text = info,
    callback = function(t)
      self[setting] = ((t.hour or 0) * 60 + (t.min or 0)) * 60
      self[setting] = Math.clamp(self[setting], range[1], range[2])
      G_reader_settings:save(setting, self[setting])
      self:_unschedule()
      self:_start()
      if menu then
        menu:updateItems()
      end
      local time_string = datetime.secondsToClockDuration(
        "letters",
        self[setting],
        true,
        true
      )
      UIManager:show(InfoMessage:new({
        text = T(gettext("%1: %2"), title, time_string),
        timeout = 3,
      }))
    end,
    default_value = datetime.secondsToClockDuration(
      "letters",
      default_value,
      true,
      true
    ),
    default_callback = function()
      time_spinner:update(
        nil,
        nil,
        nil,
        math.floor(default_value * (1 / 3600)),
        math.floor(default_value * (1 / 60)) % 60
      ) -- It is ok to pass nils here.
    end,
    extra_text = gettext("Disable"),
    extra_callback = function(this)
      self[setting] = -1 -- disable with a negative time/number
      G_reader_settings:save(setting, -1)
      self:_unschedule()
      self:_start()
      if menu then
        menu:updateItems()
      end
      UIManager:show(InfoMessage:new({
        text = T(gettext("%1: disabled"), title),
        timeout = 3,
      }))
      this:onExit()
    end,
    keep_shown_on_apply = true,
  })
  UIManager:show(time_spinner)
end

function AutoSuspend:addToMainMenu(menu_items)
  -- Device:canSuspend() check elided because it's a plugin requirement
  menu_items.autosuspend = {
    checked_func = function()
      return self:_enabled()
    end,
    text_func = function()
      if
        self.auto_suspend_timeout_seconds
        and self.auto_suspend_timeout_seconds > 0
      then
        local time_string = datetime.secondsToClockDuration(
          "letters",
          self.auto_suspend_timeout_seconds,
          true,
          true
        )
        return T(gettext("Autosuspend timeout: %1"), time_string)
      else
        return gettext("Autosuspend timeout")
      end
    end,
    keep_menu_open = true,
    callback = function(menu)
      -- 60 sec (1') is the minimum and 24*3600 sec (1day) is the maximum suspend time.
      -- A suspend time of one day seems to be excessive.
      -- But it might make sense for battery testing.
      self:pickTimeoutValue(
        menu,
        gettext("Timeout for autosuspend"),
        gettext("Enter time in hours and minutes."),
        "auto_suspend_timeout_seconds",
        default_auto_suspend_timeout_seconds,
        { 60, 24 * 3600 }
      )
    end,
  }
end

return AutoSuspend
