local Device = require("device")

if Device:isKindle() then
  -- No obvious reason to enable to plugin on kindles since they do have
  -- auto suspend logic internally.
  return { disabled = true }
end

-- If a device can power off or go into standby, it can also suspend ;).
if not Device:canSuspend() then
  return { disabled = true }
end

local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
local Math = require("optmath")
local NetworkMgr = require("ui/network/manager")
local PluginShare = require("pluginshare")
local PowerD = Device:getPowerDevice()
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local gettext = require("gettext")
local logger = require("logger")
local time = require("ui/time")
local T = require("ffi/util").template

local default_autoshutdown_timeout_seconds = 3 * 24 * 60 * 60 -- three days
local default_auto_suspend_timeout_seconds = 15 * 60 -- 15 minutes
local default_auto_standby_timeout_seconds = 4 -- 4 seconds; should be safe on Kobo/Sage
local default_standby_timeout_after_resume_seconds = 4 -- 4 seconds; should be safe on Kobo/Sage, not customizable
local default_kindle_t1_timeout_reset_seconds = 5 * 60 -- 5 minutes (i.e., half of the standard t1 timeout).

local AutoSuspend = BackgroundTaskPlugin:extend({
  name = "autosuspend",
  is_doc_only = false,
  autoshutdown_timeout_seconds = default_autoshutdown_timeout_seconds,
  auto_suspend_timeout_seconds = default_auto_suspend_timeout_seconds,
  auto_standby_timeout_seconds = default_auto_standby_timeout_seconds,
  is_standby_prevented = false,
  unexpected_wakeup = false,
  just_resumed = false,
  going_to_suspend = false,
})

function AutoSuspend:_enabledStandby()
  return Device:canStandby() and self.auto_standby_timeout_seconds > 0
end

function AutoSuspend:_enabled()
  -- NOTE: Plugin is only enabled if Device:canSuspend(), so we can elide the check here
  return self.auto_suspend_timeout_seconds > 0
end

function AutoSuspend:_enabledShutdown()
  return Device:canPowerOff() and self.autoshutdown_timeout_seconds > 0
end

function AutoSuspend:_init()
  -- NOP to prevent SwitchPlugin automatic initialization.
  -- We manage our own settings and lifecycle.
end

function AutoSuspend:_setupTask()
  local should_be_enabled = self:_enabled()
    or self:_enabledShutdown()
    or self:_enabledStandby()
    or Device:isKindle()
  if should_be_enabled then
    if not self.enabled then
      self.enabled = true
      self.settings_id = self.settings_id + 1
      BackgroundTaskPlugin._start(self)
    end
  else
    if self.enabled then
      self.enabled = false
      self.settings_id = self.settings_id + 1
    end
  end
end

function AutoSuspend:_checkTask()
  local idle_time = UIManager:timeSinceLastUserAction()

  if Device:isKindle() then
    self:_checkKindleT1(idle_time)
  end

  self:_checkSuspendShutdown(idle_time)
  self:_checkStandby(idle_time)
end

function AutoSuspend:_checkSuspendShutdown(idle_time)
  if not self:_enabled() and not self:_enabledShutdown() then
    return
  end

  local suspend_delay_seconds, shutdown_delay_seconds
  local is_charging
  if Device:hasAuxBattery() and PowerD:isAuxBatteryConnected() then
    is_charging = PowerD:isAuxCharging() and not PowerD:isAuxCharged()
  else
    is_charging = PowerD:isCharging() and not PowerD:isCharged()
  end

  if PluginShare.pause_auto_suspend or is_charging then
    suspend_delay_seconds = self.auto_suspend_timeout_seconds
    shutdown_delay_seconds = self.autoshutdown_timeout_seconds
  else
    suspend_delay_seconds = self.auto_suspend_timeout_seconds
      - time.to_number(idle_time)
    shutdown_delay_seconds = self.autoshutdown_timeout_seconds
      - time.to_number(idle_time)
  end

  if self:_enabledShutdown() and shutdown_delay_seconds <= 0 then
    logger.dbg("AutoSuspend: initiating shutdown")
    UIManager:poweroff_action()
  elseif
    self:_enabled()
    and suspend_delay_seconds <= 0
    and not self.unexpected_wakeup
  then
    logger.dbg("AutoSuspend: will suspend the device")
    UIManager:suspend()
  end
end

function AutoSuspend:_checkStandby(idle_time)
  if not self:_enabledStandby() or self.going_to_suspend then
    return
  end

  local standby_delay_seconds
  if NetworkMgr:isWifiOn() then
    standby_delay_seconds = self.auto_standby_timeout_seconds
  elseif
    Device.powerd:isCharging() and not Device:canPowerSaveWhileCharging()
  then
    standby_delay_seconds = self.auto_standby_timeout_seconds
  else
    standby_delay_seconds = self.auto_standby_timeout_seconds
      - time.to_number(idle_time)
    if self.just_resumed and standby_delay_seconds <= 0 then
      standby_delay_seconds = self.auto_standby_timeout_seconds
    end
  end

  self.just_resumed = false

  if standby_delay_seconds <= 0 then
    if self.is_standby_prevented then
      self:allowStandby()
    end
  else
    if not self.is_standby_prevented then
      self:preventStandby()
    end
  end
end

function AutoSuspend:_checkKindleT1(idle_time)
  if not self:_enabled() then
    return
  end

  local idle_s = time.to_number(idle_time)
  if idle_s >= default_kindle_t1_timeout_reset_seconds then
    local current_threshold =
      math.floor(idle_s / default_kindle_t1_timeout_reset_seconds)
    if
      not self.last_kindle_t1_reset_idle_time
      or current_threshold
        > math.floor(
          self.last_kindle_t1_reset_idle_time
            / default_kindle_t1_timeout_reset_seconds
        )
    then
      logger.dbg("AutoSuspend: will reset Kindle T1 timeout")
      PowerD:resetT1Timeout()
      self.last_kindle_t1_reset_idle_time = idle_s
    end
  else
    self.last_kindle_t1_reset_idle_time = nil
  end
end

function AutoSuspend:_onLeftStandby()
  self.just_resumed = true
  if self:_enabledStandby() then
    self:preventStandby()
  end
end

function AutoSuspend:_cleanup_standby_lock()
  if self.is_standby_prevented then
    UIManager:allowStandby()
    self.is_standby_prevented = false
  end
end

function AutoSuspend:init()
  logger.dbg("AutoSuspend: init")
  self.autoshutdown_timeout_seconds = G_reader_settings:read(
    "autoshutdown_timeout_seconds",
    default_autoshutdown_timeout_seconds
  )
  self.auto_suspend_timeout_seconds = G_reader_settings:read(
    "auto_suspend_timeout_seconds",
    default_auto_suspend_timeout_seconds
  )
  self.auto_standby_timeout_seconds =
    G_named_settings.auto_standby_timeout_seconds()

  self.is_standby_prevented = false
  self.unexpected_wakeup = false
  self.just_resumed = false
  self.going_to_suspend = false
  self.last_kindle_t1_reset_idle_time = nil

  self.settings_id = 0

  self.when = 10
  self.executable = function()
    self:_checkTask()
  end

  self:toggleStandbyHandler(self:_enabledStandby())
  if self:_enabledStandby() then
    self:preventStandby()
  end
  self:_setupTask()

  if not self.ui or not self.ui.menu then
    return
  end
  self.ui.menu:registerToMainMenu(self)
end

function AutoSuspend:onClose()
  logger.dbg("AutoSuspend: onClose")
  self:_cleanup_standby_lock()
  self.enabled = false
  self.settings_id = self.settings_id + 1
end

function AutoSuspend:preventStandby()
  logger.dbg("AutoSuspend: preventStandby")
  if not self.is_standby_prevented then
    UIManager:preventStandby()
    self.is_standby_prevented = true
  end
end

function AutoSuspend:allowStandby()
  logger.dbg("AutoSuspend: allowStandby")
  if self.is_standby_prevented then
    UIManager:allowStandby()
    self.is_standby_prevented = false
  end
end

function AutoSuspend:onSuspend()
  logger.dbg("AutoSuspend: onSuspend")
  self:_cleanup_standby_lock()
  if self:_enabledShutdown() and Device.wakeup_mgr then
    Device.wakeup_mgr:addTask(
      self.autoshutdown_timeout_seconds,
      UIManager.poweroff_action
    )
  end

  if self:_enabledStandby() and not self.going_to_suspend then
    UIManager:preventStandby()
  end

  self.going_to_suspend = true

  self.enabled = false
  self.settings_id = self.settings_id + 1
end

function AutoSuspend:onResume()
  logger.dbg("AutoSuspend: onResume")

  if self:_enabledStandby() and self.going_to_suspend then
    UIManager:allowStandby()
  end
  self.going_to_suspend = false

  if self:_enabledShutdown() and Device.wakeup_mgr then
    Device.wakeup_mgr:removeTasks(nil, UIManager.poweroff_action)
  end

  self.just_resumed = true
  self:_setupTask()
end

function AutoSuspend:onUnexpectedWakeupLimit()
  logger.dbg("AutoSuspend: onUnexpectedWakeupLimit")
  self.unexpected_wakeup = true
end

function AutoSuspend:onNotCharging()
  logger.dbg("AutoSuspend: onNotCharging")
  self.unexpected_wakeup = false
end

-- time_scale:
-- 2 ... display day:hour
-- 1 ... display hour:min
-- else ... display min:sec
function AutoSuspend:pickTimeoutValue(
  menu,
  title,
  info,
  setting,
  default_value,
  range,
  time_scale
)
  -- NOTE: if is_day_hour then time.hour stands for days and time.min for hours

  local InfoMessage = require("ui/widget/infomessage")
  local DateTimeWidget = require("ui/widget/datetimewidget")

  local setting_val = self[setting] > 0 and self[setting] or default_value

  -- Standby uses a different scheduled task than suspend/shutdown
  local is_standby = setting == "auto_standby_timeout_seconds"

  local day, hour, minute, second
  local day_max, hour_max, min_max, sec_max
  if time_scale == 2 then
    day = math.floor(setting_val * (1 / (24 * 3600)))
    hour = math.floor(setting_val * (1 / 3600)) % 24
    day_max = math.floor(range[2] * (1 / (24 * 3600))) - 1
    hour_max = 23
  elseif time_scale == 1 then
    hour = math.floor(setting_val * (1 / 3600))
    minute = math.floor(setting_val * (1 / 60)) % 60
    hour_max = math.floor(range[2] * (1 / 3600)) - 1
    min_max = 59
  else
    minute = math.floor(setting_val * (1 / 60))
    second = math.floor(setting_val) % 60
    min_max = math.floor(range[2] * (1 / 60)) - 1
    sec_max = 59
  end

  local time_spinner
  time_spinner = DateTimeWidget:new({
    day = day,
    hour = hour,
    min = minute,
    sec = second,
    day_hold_step = 5,
    hour_hold_step = 5,
    min_hold_step = 10,
    sec_hold_step = 10,
    day_max = day_max,
    hour_max = hour_max,
    min_max = min_max,
    sec_max = sec_max,
    ok_text = gettext("Set timeout"),
    title_text = title,
    info_text = info,
    callback = function(t)
      self[setting] = (((t.day or 0) * 24 + (t.hour or 0)) * 60 + (t.min or 0))
          * 60
        + (t.sec or 0)
      self[setting] = Math.clamp(self[setting], range[1], range[2])
      G_reader_settings:save(setting, self[setting])
      self:_cleanup_standby_lock()
      if is_standby then
        self:toggleStandbyHandler(self:_enabledStandby())
      end
      self:_setupTask()
      if menu then
        menu:updateItems()
      end
      local time_string = datetime.secondsToClockDuration(
        "letters",
        self[setting],
        time_scale == 2 or time_scale == 1,
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
      time_scale == 2 or time_scale == 1,
      true
    ),
    default_callback = function()
      local day, hour, min, sec -- luacheck: ignore 431
      if time_scale == 2 then
        day = math.floor(default_value * (1 / (24 * 3600)))
        hour = math.floor(default_value * (1 / 3600)) % 24
      elseif time_scale == 1 then
        hour = math.floor(default_value * (1 / 3600))
        min = math.floor(default_value * (1 / 60)) % 60
      else
        min = math.floor(default_value * (1 / 60))
        sec = math.floor(default_value % 60)
      end
      time_spinner:update(nil, nil, day, hour, min, sec) -- It is ok to pass nils here.
    end,
    extra_text = gettext("Disable"),
    extra_callback = function(this)
      self[setting] = -1 -- disable with a negative time/number
      G_reader_settings:save(setting, -1)
      self:_cleanup_standby_lock()
      if is_standby then
        self:toggleStandbyHandler(false)
      end
      self:_setupTask()
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
        { 60, 24 * 3600 },
        1
      )
    end,
  }
  if Device:canPowerOff() then
    menu_items.autoshutdown = {
      checked_func = function()
        return self:_enabledShutdown()
      end,
      text_func = function()
        if
          self.autoshutdown_timeout_seconds
          and self.autoshutdown_timeout_seconds > 0
        then
          local time_string = datetime.secondsToClockDuration(
            "letters",
            self.autoshutdown_timeout_seconds,
            true,
            true
          )
          return T(gettext("Autoshutdown timeout: %1"), time_string)
        else
          return gettext("Autoshutdown timeout")
        end
      end,
      keep_menu_open = true,
      callback = function(menu)
        -- 5*60 sec (5') is the minimum and 28*24*3600 (28days) is the maximum shutdown time.
        -- Minimum time has to be big enough, to avoid start-stop death scenarios.
        -- Maximum more than four weeks seems a bit excessive if you want to enable authoshutdown,
        -- even if the battery can last up to three months.
        self:pickTimeoutValue(
          menu,
          gettext("Timeout for autoshutdown"),
          gettext("Enter time in days and hours."),
          "autoshutdown_timeout_seconds",
          default_autoshutdown_timeout_seconds,
          { 5 * 60, 28 * 24 * 3600 },
          2
        )
      end,
    }
  end
  if Device:canStandby() then
    local standby_help = gettext(
      [[Standby puts the device into a power-saving state in which the screen is on and user input can be performed.

Standby can not be entered if Wi-Fi is on.

Upon user input, the device needs a certain amount of time to wake up. Generally, the newer the device, the less noticeable this delay will be, but it can be fairly aggravating on slower devices.]]
    )
    -- Add a big fat warning on unreliable NTX boards
    if Device:isKobo() and not Device:hasReliableMxcWaitFor() then
      standby_help = standby_help
        .. "\n"
        .. gettext(
          [[Your device is known to be extremely unreliable, as such, failure to enter a power-saving state *may* hang the kernel, resulting in a full device hang or a device restart.]]
        )
    end

    menu_items.autostandby = {
      checked_func = function()
        return self:_enabledStandby()
      end,
      text_func = function()
        if
          self.auto_standby_timeout_seconds
          and self.auto_standby_timeout_seconds > 0
        then
          local time_string = datetime.secondsToClockDuration(
            "letters",
            self.auto_standby_timeout_seconds,
            false,
            true,
            true
          )
          return T(gettext("Autostandby timeout: %1"), time_string)
        else
          return gettext("Autostandby timeout")
        end
      end,
      help_text = standby_help,
      keep_menu_open = true,
      callback = function(menu)
        -- 4 sec is the minimum and 15*60 sec (15min) is the maximum standby time.
        -- We need a minimum time, so that scheduled function have a chance to execute.
        -- A standby time of 15 min seem excessive.
        -- But or battery testing it might give some sense.
        self:pickTimeoutValue(
          menu,
          gettext("Timeout for autostandby"),
          gettext("Enter time in minutes and seconds."),
          "auto_standby_timeout_seconds",
          default_auto_standby_timeout_seconds,
          { 1, 15 * 60 },
          0
        )
      end,
    }
  end
end

-- KOReader is merely waiting for user input right now.
-- UI signals us that standby is allowed at this very moment because nothing else goes on in the background.
-- NOTE: To make sure this will not even run when autostandby is disabled,
--     this is only aliased as `onAllowStandby` when necessary.
--     (Because the Event is generated regardless of us, as many things can call UIManager:allowStandby).
function AutoSuspend:AllowStandbyHandler()
  logger.dbg("AutoSuspend: onAllowStandby")
  -- This piggy-backs minimally on the UI framework implemented for the PocketBook autostandby plugin,
  -- see its own AllowStandby handler for more details.

  local wake_in
  -- Wake up before the next scheduled function executes (e.g. footer update, suspend ...)
  local next_task_time = UIManager:getNextTaskTime()
  if next_task_time then
    -- Wake up slightly after the formerly scheduled event,
    -- to avoid resheduling the same function after a fraction of a second again (e.g. don't draw footer twice).
    wake_in = math.floor(time.to_number(next_task_time)) + 1
  else
    wake_in = math.huge
  end

  if wake_in >= 1 then -- Don't go into standby, if scheduled wakeup is in less than 1 second.
    logger.dbg(
      "AutoSuspend: entering standby with a wakeup alarm in",
      wake_in,
      "s"
    )

    -- This obviously needs a matching implementation in Device, the canonical one being Kobo.
    Device:standby(wake_in)

    logger.dbg(
      "AutoSuspend: left standby after",
      time.format_time(Device.last_standby_time),
      "s"
    )

    -- NOTE: UIManager consumes scheduled tasks before input events,
    --     solely because of where we run inside an UI frame (via UIManager:_standbyTransition):
    --     we're neither a scheduled task nor an input event, we run *between* scheduled tasks and input polling.
    --     That means we go straight to input polling when returning, *without* a trip through the task queue
    --     (c.f., UIManager:_checkTasks in UIManager:handleInput).

    UIManager:shiftScheduledTasksBy(-Device.last_standby_time) -- correct scheduled times by last_standby_time

    -- Since we go straight to input polling, and that our time spent in standby won't have affected the already computed
    -- input polling deadline (because MONOTONIC doesn't tick during standby/suspend),
    -- tweak said deadline to make sure poll will return immediately, so we get a chance to run through the task queue ASAP.
    -- This shouldn't prevent us from actually consuming any pending input events first,
    -- because if we were woken up by user input, those events should already be in the evdev queue...
    UIManager:consumeInputEarlyAfterPM(true)

    self:_onLeftStandby()
  else
    logger.dbg("AutoSuspend: wake_in too short, aborting standby")
    self:_onLeftStandby()
  end
end

function AutoSuspend:toggleStandbyHandler(toggle)
  if toggle then
    self.onAllowStandby = self.AllowStandbyHandler
  else
    self.onAllowStandby = nil
  end
end

return AutoSuspend
