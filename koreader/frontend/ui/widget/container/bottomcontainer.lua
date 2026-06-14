--[[--
BottomContainer contains its content (1 widget) at the bottom of its own
dimensions
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local BottomContainer = WidgetContainer:extend({})

function BottomContainer:paintTo(bb, x, y)
  self:mergePosition(x, y)
  self:getSize()
  local contentSize = self[1]:getSize()
  --- @fixme
  -- if contentSize.w > self:getSize().w or contentSize.h > self:getSize().h then
  -- throw error? paint to scrap buffer and blit partially?
  -- for now, we ignore this
  -- end
  self[1]:paintTo(
    bb,
    x + math.floor((self:getSize().w - contentSize.w) / 2),
    y + (self:getSize().h - contentSize.h)
  )
end

function BottomContainer:dirtyRegion()
  return self[1]:dirtyRegion()
end

return BottomContainer
