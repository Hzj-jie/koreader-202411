local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")

local HorizontalScrollBar = InputContainer:extend({
  enable = true,
  low = 0,
  high = 1,
  height = Size.padding.default,
  width = Size.item.height_large, -- as in VerticalScrollBar
  bordersize = Size.border.thin,
  bordercolor = Blitbuffer.COLOR_BLACK,
  radius = 0,
  rectcolor = Blitbuffer.COLOR_BLACK,
  -- minimal width of the thumb/knob/grip (usually showing the current
  -- view size and position relative to the whole scrollable width):
  min_thumb_size = Size.line.thick,
  scroll_callback = nil,
})

function HorizontalScrollBar:init()
  if Device:isTouchDevice() then
    local pan_rate = G_named_settings.low_pan_rate_or_scroll()
    self.ges_events = {
      TapScroll = {
        GestureRange:new({
          ges = "tap",
          range = function()
            return self.touch_dimen
          end,
        }),
      },
      HoldScroll = {
        GestureRange:new({
          ges = "hold",
          range = function()
            return self.touch_dimen
          end,
        }),
      },
      HoldPanScroll = {
        GestureRange:new({
          ges = "hold_pan",
          rate = pan_rate,
          range = function()
            return self.touch_dimen
          end,
        }),
      },
      HoldReleaseScroll = {
        GestureRange:new({
          ges = "hold_release",
          range = function()
            return self.touch_dimen
          end,
        }),
      },
      PanScroll = {
        GestureRange:new({
          ges = "pan",
          rate = pan_rate,
          range = function()
            return self.touch_dimen
          end,
        }),
      },
      PanScrollRelease = {
        GestureRange:new({
          ges = "pan_release",
          range = function()
            return self.touch_dimen
          end,
        }),
      },
    }
  end
end

function HorizontalScrollBar:onTapScroll(arg, ges)
  if self.scroll_callback then
    local ratio = (ges.pos.x - self.touch_dimen.x) / self.width
    if BD.mirroredUILayout() then
      ratio = 1 - ratio
    end
    self.scroll_callback(ratio)
    return true
  end
end
HorizontalScrollBar.onHoldScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onHoldPanScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onHoldReleaseScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onPanScroll = HorizontalScrollBar.onTapScroll
HorizontalScrollBar.onPanScrollRelease = HorizontalScrollBar.onTapScroll

function HorizontalScrollBar:set(low, high)
  self.low = low > 0 and low or 0
  self.high = high < 1 and high or 1
end

function HorizontalScrollBar:getRequiredHeight()
  -- We need to reserve space for the scrollbar itself (1x height),
  -- the touch zone extensions on both sides (2x height),
  -- and a 5px safety margin on the inner side next to the content.
  return 3 * self.height + Device.screen:scaleBySize(5)
end

function HorizontalScrollBar:paintTo(bb, x, y)
  self:mergePosition(x, y)
  if not self.enable then
    return
  end
  self.touch_dimen = Geom:new({
    x = x,
    y = y - self.height,
    w = self.width,
    h = 3 * self.height,
  })
  if self.height > 0 and self.bordersize > 0 then
    bb:paintRect(
      x,
      y - self.height,
      self.width,
      self.bordersize,
      self.bordercolor
    )
  end
  -- Reset the area first.
  bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
  bb:paintBorder(
    x,
    y,
    self.width,
    self.height,
    self.bordersize,
    self.bordercolor,
    self.radius
  )
  if BD.mirroredUILayout() then
    bb:paintRect(
      x + self.bordersize + (1 - self.high) * self.width,
      y + self.bordersize,
      math.max(
        (self.width - 2 * self.bordersize) * (self.high - self.low),
        self.min_thumb_size
      ),
      self.height - 2 * self.bordersize,
      self.rectcolor
    )
  else
    bb:paintRect(
      x + self.bordersize + self.low * self.width,
      y + self.bordersize,
      math.max(
        (self.width - 2 * self.bordersize) * (self.high - self.low),
        self.min_thumb_size
      ),
      self.height - 2 * self.bordersize,
      self.rectcolor
    )
  end
end

return HorizontalScrollBar
