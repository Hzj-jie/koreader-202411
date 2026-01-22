--[[--
LeftContainer aligns its content (1 widget) at the left of its own dimensions
--]]

local BD = require("ui/bidi")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local LeftContainer = WidgetContainer:extend({
  allow_mirroring = true,
})

function LeftContainer:paintTo(bb, x, y)
  self:mergePosition(x, y)
  local contentSize = self[1]:getSize()
  --- @fixme
  -- if contentSize.w > self.dimen.w or contentSize.h > self.dimen.h then
  -- throw error? paint to scrap buffer and blit partially?
  -- for now, we ignore this
  -- end
  if BD.mirroredUILayout() and self.allow_mirroring then
    x = x + (self.dimen.w - contentSize.w) -- as in RightContainer
  end
  y = y + math.floor((self.dimen.h - contentSize.h) / 2)
  self[1]:paintTo(bb, x, y)
end

function LeftContainer:dirtyRegion()
  return self[1]:dirtyRegion()
end

return LeftContainer
