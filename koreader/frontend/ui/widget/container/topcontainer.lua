--[[--
TopContainer contains its content (1 widget) at the top of its own dimensions
--]]

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local TopContainer = WidgetContainer:extend({})

function TopContainer:dirtyRegion()
  return self[1]:dirtyRegion()
end

return TopContainer
