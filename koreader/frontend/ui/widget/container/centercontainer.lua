--[[--
CenterContainer centers its content (1 widget) within its own dimensions
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CenterContainer = WidgetContainer:extend({})

function CenterContainer:paintTo(bb, x, y)
  assert(self.dimen ~= nil)
  self.dimen.x = x
  self.dimen.y = y
  local content_size = self[1]:getSize()

  -- check if content is bigger than container
  if self.ignore_if_over == "height" then -- align upper borders
    if self.dimen.h < content_size.h then
      self.ignore = "height"
    end
  elseif self.ignore_if_over == "width" then -- align left borders
    if self.dimen.w < content_size.w then
      self.ignore = "width"
    end
  end

  if self.ignore ~= "height" then
    y = y + math.floor((self.dimen.h - content_size.h) / 2)
  end
  if self.ignore ~= "width" then
    x = x + math.floor((self.dimen.w - content_size.w) / 2)
  end
  self[1]:paintTo(bb, x, y)
end

return CenterContainer
