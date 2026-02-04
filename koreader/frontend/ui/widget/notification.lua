--[[--
Widget that displays a tiny notification at the top of the screen.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RectSpan = require("ui/widget/rectspan")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local gettext = require("gettext")
local time = require("ui/time")
local Screen = Device.screen
local Input = Device.input

local Notification = InputContainer:extend({
  face = Font:getFace("x_smallinfofont"),
  text = gettext("N/A"),
  margin = Size.margin.default,
  padding = Size.padding.default,
  timeout = 2, -- default to 2 seconds
  _timeout_func = nil,
  toast = true, -- closed on any event, and let the event propagate to next top widget

  _shown_list = {}, -- actual static class member, array of stacked notifications (value is show (well, init) time or false).
  _shown_idx = nil, -- index of this instance in the class's _shown_list array (assumes each Notification object is only shown (well, init) once).
})

function Notification:init()
  if not self.toast then
    -- If not toast, closing is handled in here
    if Device:hasKeys() then
      self.key_events.AnyKeyPressed = { { Input.group.Any } }
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
  end

  local text_widget = TextWidget:new({
    text = self.text,
    face = self.face,
    max_width = Screen:getWidth() - 2 * (self.margin + self.padding),
  })
  local widget_size = text_widget:getSize()
  self.frame = FrameContainer:new({
    background = Blitbuffer.COLOR_WHITE,
    radius = 0,
    margin = self.margin,
    padding = self.padding,
    CenterContainer:new({
      dimen = Geom:new({
        w = widget_size.w,
        h = widget_size.h,
      }),
      text_widget,
    }),
  })
  local notif_height = self.frame:getSize().h

  self:_cleanShownStack()
  table.insert(Notification._shown_list, time.monotonic())
  self._shown_idx = #Notification._shown_list

  self[1] = VerticalGroup:new({
    align = "center",
    -- We use a span to properly position this notification:
    RectSpan:new({
      -- have this VerticalGroup full width, to ensure centering
      width = Screen:getWidth(),
      -- push this frame at its y=self._shown_idx position
      height = notif_height * (self._shown_idx - 1) + self.margin,
      -- (let's add a leading self.margin to get the same distance
      -- from top of screen to first notification top border as
      -- between borders of next notifications)
    }),
    self.frame,
  })
end

-- Display a notification popup
function Notification:notify(arg)
  UIManager:show(Notification:new({
    text = arg,
  }))
end

function Notification:_cleanShownStack()
  -- Clean stack of shown notifications
  if self._shown_idx then
    -- If this field exists, this is the first time this instance was closed since its init.
    -- This notification is no longer displayed
    Notification._shown_list[self._shown_idx] = false
  end
  -- We remove from the stack's tail all slots no longer displayed.
  -- Even if slots at top are available, we'll keep adding new
  -- notifications only at the tail/bottom (easier for the eyes
  -- to follow what is happening).
  -- As a sanity check, we also forget those shown for
  -- more than 30s in case no close event was received.
  local expire_time = time.monotonic() - time.s(30)
  for i = #Notification._shown_list, 1, -1 do
    if Notification._shown_list[i] and Notification._shown_list[i] > expire_time then
      break -- still shown (or not yet expired)
    end
    table.remove(Notification._shown_list, i)
  end
end

function Notification:onClose()
  self:_cleanShownStack()
  self._shown_idx = nil -- Don't do something stupid if this same instance gets closed multiple times
  UIManager:setDirty(nil, function()
    return "ui", self.frame.dimen
  end)
  -- If we were closed early, drop the scheduled timeout
  if self._timeout_func then
    UIManager:unschedule(self._timeout_func)
    self._timeout_func = nil
  end
end

function Notification:onShow()
  UIManager:setDirty(self, function()
    return "ui", self.frame.dimen
  end)
  if self.timeout then
    self._timeout_func = function()
      self._timeout_func = nil
      UIManager:close(self)
    end
    UIManager:scheduleIn(self.timeout, self._timeout_func)
  end

  return true
end

function Notification:onTapClose()
  if self.toast then
    return
  end -- should not happen
  UIManager:close(self)
  return true
end
Notification.onAnyKeyPressed = Notification.onTapClose

-- Toasts should go bye-bye on user input, without stopping the event's propagation.
function Notification:onKeyPress(key)
  if self.toast then
    UIManager:close(self)
    return false
  end
  return InputContainer.onKeyPress(self, key)
end
function Notification:onKeyRepeat(key)
  if self.toast then
    UIManager:close(self)
    return false
  end
  return InputContainer.onKeyRepeat(self, key)
end
function Notification:onGesture(ev)
  if self.toast then
    UIManager:close(self)
    return false
  end
  return InputContainer.onGesture(self, ev)
end

-- Since toasts do *not* prevent event propagation, if we let this go through to InputContainer, shit happens...
function Notification:onIgnoreTouchInput(toggle)
  return true
end
-- Do the same for other Events caught by our base class
Notification.onResume = Notification.onIgnoreTouchInput
Notification.onPhysicalKeyboardDisconnected = Notification.onIgnoreTouchInput
Notification.onInput = Notification.onIgnoreTouchInput

return Notification
