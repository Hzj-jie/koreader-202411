--[[--
Widget that displays a line.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Widget = require("ui/widget/widget")

local LineWidget = Widget:extend({
  style = "solid",
  background = Blitbuffer.COLOR_BLACK,
  dimen = nil,
  --- @todo Replay dirty hack here  13.03 2013 (houqp).
  empty_segments = nil,
})

function LineWidget:paintTo(bb, x, y)
  if self.style == "none" then
    return
  end
  if self.style == "dashed" then
    for i = 0, self:getSize().w - 20, 20 do
      bb:paintRect(x + i, y, 16, self:getSize().h, self.background)
    end
  else
    if self.empty_segments then
      bb:paintRect(
        x,
        y,
        self.empty_segments[1].s,
        self:getSize().h,
        self.background
      )
      bb:paintRect(
        x + self.empty_segments[1].e,
        y,
        self:getSize().w - x - self.empty_segments[1].e,
        self:getSize().h,
        self.background
      )
    else
      bb:paintRect(x, y, self:getSize().w, self:getSize().h, self.background)
    end
  end
end

return LineWidget
