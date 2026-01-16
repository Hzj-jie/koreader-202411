local Widget = require("ui/widget/widget")
local logger = require("logger")

--[[
Dummy Widget that reserves horizontal space
--]]
local HorizontalSpan = Widget:extend({
  width = 0,
})

return HorizontalSpan
