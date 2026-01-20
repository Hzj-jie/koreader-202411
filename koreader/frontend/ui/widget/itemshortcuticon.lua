local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

--[[--
Widget that displays a shortcut icon for menu item.
--]]
local ItemShortCutIcon = WidgetContainer:extend({
  dimen = nil,
  key = nil,
  bordersize = Size.border.default,
  style = "square",
})

function ItemShortCutIcon:init()
  if not self.key then
    return
  end
  self:initSize(Screen:scaleBySize(22), Screen:scaleBySize(22))

  local background = Blitbuffer.COLOR_WHITE
  if self.style == "grey_square" then
    background = Blitbuffer.COLOR_LIGHT_GRAY
  end

  --- @todo Calculate font size by icon size  01.05 2012 (houqp).
  local sc_face
  if self.key:len() > 1 then
    sc_face = Font:getFace("ffont", 14)
  else
    sc_face = Font:getFace("scfont", 22)
  end

  self[1] = FrameContainer:new({
    padding = 0,
    bordersize = self.bordersize,
    background = background,
    dimen = self.dimen:copy(),
    CenterContainer:new({
      dimen = self.dimen:copy(),
      TextWidget:new({
        text = self.key,
        face = sc_face,
      }),
    }),
  })
end

return ItemShortCutIcon
