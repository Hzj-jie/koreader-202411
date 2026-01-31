local Widget = require("ui/widget/widget")

--[[
Dummy Widget that reserves horizontal space
--]]
local HorizontalSpan = Widget:extend({
  width = 0,
})

return HorizontalSpan
