--[[Generated from clock.moon]]
local Device = require("device")
local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare = require("pluginshare")
local UIManager = require("ui/uimanager")
local Input = Device.input
local Screen = Device.screen
local ClockWidget = require("clockwidget")
local Size = require("ui/size")
local gettext = require("gettext")
local Clock = InputContainer:new({
  name = "clock",
  is_doc_only = false,
  modal = true,
  width = Screen:getWidth(),
  height = Screen:getHeight(),
  scale_factor = 0,
  _visible = false,
})
Clock.init = function(self)
  if Device:hasKeys() then
    self.key_events = {
      AnyKeyPressed = {
        {
          Input.group.Any,
        },
        seqtext = "any key",
        doc = "close dialog",
      },
    }
  end
  if Device:isTouchDevice() then
    self.ges_events.TapClose = {
      GestureRange:new({
        ges = "tap",
        range = Geom:new({
          x = 0,
          y = 0,
          w = Screen:getWidth(),
          h = Screen:getHeight(),
        }),
      }),
    }
  end
  local width, height
  width, height = self.width, self.height
  local padding = Size.padding.fullscreen
  self[1] = ClockWidget:new({
    width = width,
    height = height,
    padding = padding,
  })
  self.ui.menu:registerToMainMenu(self)
  return self:onDispatcherRegisterAction()
end
Clock.addToMainMenu = function(self, menu_items)
  menu_items.clock = {
    text = gettext("Clock"),
    callback = function()
      self:onClockShow()
    end,
  }
end
Clock.onClose = function(self)
  UIManager:setDirty(nil, function()
    return "ui", self[1].dimen
  end)
end
Clock.onShow = function(self)
  if self.timeout then
    UIManager:scheduleIn(self.timeout, function()
      return UIManager:close(self)
    end)
  end
  PluginShare.pause_auto_suspend = true
end
Clock.onSuspend = function(self)
  if
    G_reader_settings:read("clock_on_suspend") and not self._was_suspending
  then
    UIManager:show(self)
    self._was_suspending = true
  end
end
Clock.onResume = function(self)
  if self._was_suspending then
    self:onShow()
  end
  self._was_suspending = false
end
Clock.onTapClose = function(self)
  if not self._visible then
    return false
  end
  PluginShare.pause_auto_suspend = false
  self._was_suspending = false
  self._visible = false
  UIManager:close(self)
  return true
end
Clock.onAnyKeyPressed = function(self)
  return self:onTapClose()
end
Clock.onClockShow = function(self)
  self._visible = true
  UIManager:show(self)
  return true
end
Clock.onDispatcherRegisterAction = function(self)
  return Dispatcher:registerAction("clock_show", {
    category = "none",
    event = "ClockShow",
    title = gettext("Show clock"),
    device = true,
  })
end
return Clock
