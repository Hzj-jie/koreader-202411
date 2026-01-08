--[[--
An UnderlineContainer is a WidgetContainer that is able to paint
a line under its child node.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local UnderlineContainer = WidgetContainer:extend({
  linesize = Size.line.thick,
  padding = Size.padding.tiny,
  -- We default to white to be invisible by default for FocusManager use-cases (only switching to black @ onFocus)
  color = Blitbuffer.COLOR_WHITE,
  vertical_align = "top",
})

function UnderlineContainer:paintTo(bb, x, y)
  local content_size = self[1]:getSize()
  self:mergeDimen(x, y, content_size)
  self.dimen.h = self.dimen.h + self.linesize + 2 * self.padding
  local p_y = y
  if self.vertical_align == "center" then
    p_y = math.floor((self.dimen.h - content_size.h) / 2) + y
  elseif self.vertical_align == "bottom" then
    p_y = (self.dimen.h - content_size.h) + y
  end
  self[1]:paintTo(bb, x, p_y)
  bb:paintRect(
    x,
    y + self.dimen.h - self.linesize,
    self.dimen.w,
    self.linesize,
    self.color
  )
end

return UnderlineContainer
