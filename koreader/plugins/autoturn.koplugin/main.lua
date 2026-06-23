local BackgroundTaskPlugin = require("ui/plugin/background_task_plugin")
local Event = require("ui/event")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local datetime = require("datetime")
local gettext = require("gettext")
local logger = require("logger")
local time = require("ui/time")
local T = require("ffi/util").template

local AutoTurn = BackgroundTaskPlugin:extend({
  is_doc_only = true,
})

function AutoTurn:new(o)
  o = o or {}
  o.name = "autoturn"
  o.default_enable = false
  o.when = "asap"
  local instance
  o.executable = function()
    AutoTurn._action(instance or o)
  end
  o.menu_item = "autoturn"

  instance = BackgroundTaskPlugin.new(self, o)
  return instance
end

function AutoTurn:_init()
  self.autoturn_sec = self.settings:read("autoturn_timeout_seconds") or 0
  self.autoturn_distance = self.settings:read("autoturn_distance") or 1
  BackgroundTaskPlugin._init(self)
end

function AutoTurn:_enabled()
  return self.enabled and self.autoturn_sec > 0
end

function AutoTurn:_action()
  if
    PluginShare.DeviceIdling == true
    or not self:_enabled()
    or (UIManager:getTopmostVisibleWidget() or {}).name ~= "ReaderUI"
  then
    return
  end

  -- This is tricky, if user explicitly turns or whatever, wait until next time.
  local delay = time.s(self.autoturn_sec) - UIManager:timeSinceLastUserAction()
  if delay > 0 then
    return
  end

  logger.dbg("AutoTurn: go to next page")
  UIManager:broadcastEvent(Event:new("GotoViewRel", self.autoturn_distance))
  -- Treat it as a user action.
  UIManager:updateLastUserActionTime()
end

function AutoTurn:_start()
  if not self:_enabled() then
    return
  end

  BackgroundTaskPlugin._start(self)
  PluginShare.pause_auto_suspend = true

  -- Show info message if enabled and started
  logger.dbg(
    "AutoTurn: start at",
    time.format_time(UIManager:getElapsedTimeSinceBoot())
  )
  local text
  if self.autoturn_distance == 1 then
    local time_string = datetime.secondsToClockDuration(
      "letters",
      self.autoturn_sec,
      false,
      true,
      true
    )
    text = T(
      gettext(
        "Autoturn is now active and will automatically turn the page every %1."
      ),
      time_string
    )
  else
    text = T(
      gettext(
        "Autoturn is now active and will automatically scroll %1 % of the page every %2 seconds."
      ),
      self.autoturn_distance * 100,
      self.autoturn_sec
    )
  end

  local InfoMessage = require("ui/widget/infomessage")
  UIManager:show(InfoMessage:new({
    text = text,
    timeout = 3,
  }))
end

function AutoTurn:_stop()
  BackgroundTaskPlugin._stop(self)
  PluginShare.pause_auto_suspend = false
end

function AutoTurn:onClose()
  BackgroundTaskPlugin.onClose(self)
  PluginShare.pause_auto_suspend = false
end

AutoTurn.onCloseDocument = AutoTurn.onClose
AutoTurn.onSuspend = AutoTurn.onClose

function AutoTurn:onResume()
  logger.dbg("AutoTurn: onResume")
  if self:_enabled() then
    self:_start()
  end
end

function AutoTurn:addToMainMenu(menu_items)
  menu_items.autoturn = {
    text_func = function()
      local time_string = datetime.secondsToClockDuration(
        "letters",
        self.autoturn_sec,
        false,
        true,
        true
      )
      return self:_enabled() and T(gettext("Autoturn: %1"), time_string)
        or gettext("Autoturn")
    end,
    checked_func = function()
      return self:_enabled()
    end,
    callback = function(menu)
      local DateTimeWidget = require("ui/widget/datetimewidget")
      local autoturn_seconds = self.settings:read("autoturn_timeout_seconds")
        or 30
      local autoturn_minutes = math.floor(autoturn_seconds * (1 / 60))
      autoturn_seconds = autoturn_seconds % 60
      local autoturn_spin = DateTimeWidget:new({
        title_text = gettext("Autoturn time"),
        info_text = gettext("Enter time in minutes and seconds."),
        min = autoturn_minutes,
        min_max = 60 * 24, -- maximum one day
        min_default = 0,
        sec = autoturn_seconds,
        sec_default = 30,
        keep_shown_on_apply = true,
        ok_text = gettext("Set timeout"),
        cancel_text = gettext("Disable"),
        cancel_callback = function()
          self.settings:makeFalse("enable")
          self:_init()
          self:onFlushSettings()
          menu:updateItems()
        end,
        ok_always_enabled = true,
        callback = function(t)
          self.autoturn_sec = t.min * 60 + t.sec
          self.settings:save("autoturn_timeout_seconds", self.autoturn_sec)
          self.settings:makeTrue("enable")
          self:_init()
          self:onFlushSettings()
          menu:updateItems()
        end,
      })
      UIManager:show(autoturn_spin)
    end,
    hold_callback = function(menu)
      local SpinWidget = require("ui/widget/spinwidget")
      local curr_items = self.settings:read("autoturn_distance") or 1
      local autoturn_spin = SpinWidget:new({
        value = curr_items,
        value_min = -20,
        value_max = 20,
        precision = "%.2f",
        value_step = 0.1,
        value_hold_step = 0.5,
        ok_text = gettext("Set distance"),
        title_text = gettext("Scrolling distance"),
        callback = function(autoturn_spin)
          self.autoturn_distance = autoturn_spin.value
          self.settings:save("autoturn_distance", autoturn_spin.value)
          if self.enabled then
            self:_init()
          end
          self:onFlushSettings()
          menu:updateItems()
        end,
      })
      UIManager:show(autoturn_spin)
    end,
  }
end

return AutoTurn
