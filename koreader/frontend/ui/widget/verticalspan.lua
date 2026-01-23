local Widget = require("ui/widget/widget")
local logger = require("logger")

--[[
Dummy Widget that reserves vertical space
--]]
local VerticalSpan = Widget:extend({
  height = 0,
})

function VerticalSpan:getSize()
  if self.width then
    logger.warn("FixMe: VerticalSpan should have a height rather than width.")
    self.height = self.width
    self.width = nil
  end
  return Widget.getSize(self)
end

return VerticalSpan
