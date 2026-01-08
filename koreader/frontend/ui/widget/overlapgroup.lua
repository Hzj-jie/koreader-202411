--[[--
A layout widget that puts objects above each other.
--]]

local BD = require("ui/bidi")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local OverlapGroup = WidgetContainer:extend({
  -- Note: we default to allow_mirroring = true.
  -- When using LeftContainer, RightContainer or HorizontalGroup
  -- in an OverlapGroup, mostly when they take the whole width,
  -- either OverlapGroup, or all the others, need to have
  -- allow_mirroring=false (otherwise, some upper mirroring would
  -- cancel a lower one...).
  -- It's usually safer to set it to false on the OverlapGroup,
  -- but some thinking is needed when many of them are nested.
  allow_mirroring = true,
  _size = nil,
})

function OverlapGroup:getSize()
  if not self.dimen then
    self.dimen = Geom:new({ w = 0, h = 0 })
    self._offsets = { x = math.huge, y = math.huge }
    for i, widget in ipairs(self) do
      local w_size = widget:getSize()
      if self.dimen.h < w_size.h then
        self.dimen.h = w_size.h
      end
      if self.dimen.w < w_size.w then
        self.dimen.w = w_size.w
      end
    end
  end

  return self.dimen
end

function OverlapGroup:paintTo(bb, x, y)
  self:getSize()
  self.dimen.x = x
  self.dimen.y = y

  for i, wget in ipairs(self) do
    local wget_size = wget:getSize()
    local overlap_align = wget.overlap_align
    if BD.mirroredUILayout() and self.allow_mirroring then
      -- Checks in the same order as how they are checked below
      if overlap_align == "right" then
        overlap_align = "left"
      elseif overlap_align == "center" then
        overlap_align = "center"
      elseif wget.overlap_offset then
        wget.overlap_offset[1] = self.dimen.w - wget_size.w - wget.overlap_offset[1]
      else
        overlap_align = "right"
      end
      -- see if something to do with wget.overlap_offset
    end
    if overlap_align == "right" then
      wget:paintTo(bb, x + self.dimen.w - wget_size.w, y)
    elseif overlap_align == "center" then
      wget:paintTo(bb, x + math.floor((self.dimen.w - wget_size.w) / 2), y)
    elseif wget.overlap_offset then
      wget:paintTo(bb, x + wget.overlap_offset[1], y + wget.overlap_offset[2])
    else
      -- default to left
      wget:paintTo(bb, x, y)
    end
  end
end

return OverlapGroup
