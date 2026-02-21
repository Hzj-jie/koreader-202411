local Widget = require("ui/widget/widget")

--[[
Dummy Widget that reserves vertical and horizontal space
]]
local RectSpan = Widget:extend({
  width = 0,
  height = 0,
})

return RectSpan
