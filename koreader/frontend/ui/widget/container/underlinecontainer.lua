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

function UnderlineContainer:getSize()
  local contentSize = self[1]:getSize()
  self.dimen = Geom.newOrMergeSizeFrom(self.dimen, {
    w = contentSize.w,
    h = contentSize.h + self.linesize + 2 * self.padding,
  })
  return self.dimen
end

function UnderlineContainer:paintTo(bb, x, y)
  self:mergePosition(x, y)
  local container_size = self:getSize()
  local content_size = self[1]:getSize()
  local p_y = y
  if self.vertical_align == "center" then
    p_y = math.floor((container_size.h - content_size.h) / 2) + y
  elseif self.vertical_align == "bottom" then
    p_y = (container_size.h - content_size.h) + y
  end
  self[1]:paintTo(bb, x, p_y)
  bb:paintRect(
    x,
    y + container_size.h - self.linesize,
    container_size.w,
    self.linesize,
    self.color
  )
end

return UnderlineContainer
