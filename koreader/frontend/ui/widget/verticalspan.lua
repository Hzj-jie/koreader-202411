local Widget = require("ui/widget/widget")
local logger = require("logger")

--[[
Dummy Widget that reserves vertical space
--]]
local VerticalSpan = Widget:extend({
  height = 0,
})

function VerticalSpan:init()
  if self.width then
    logger.warn("FixMe: VerticalSpan should have a height rather than width")
    self.height = self.width
  end
  if not self.height then
    logger.warn("FixMe: VerticalSpan should have a height")
    self.height = 0
  end
end

return VerticalSpan
