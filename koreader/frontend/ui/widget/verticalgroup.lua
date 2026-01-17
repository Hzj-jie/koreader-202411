--[[--
A layout widget that puts objects under each other.
--]]

local BD = require("ui/bidi")
local Geom = require("ui/geometry")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local VerticalGroup = WidgetContainer:extend({
  align = "center",
  allow_mirroring = true,
  _offsets = {},
})

function VerticalGroup:getSize()
  if not self.dimen then
    self.dimen = Geom:new()
    self._offsets = {}
    for i, widget in ipairs(self) do
      local w_size = widget:getSize()
      self._offsets[i] = {
        x = w_size.w,
        y = self.dimen.h,
      }
      self.dimen.h = self.dimen.h + w_size.h
      if w_size.w > self.dimen.w then
        self.dimen.w = w_size.w
      end
    end
  end
  return self.dimen
end

function VerticalGroup:paintTo(bb, x, y)
  local size = self:getSize()
  self:mergePosition(x, y)
  local align = self.align
  if BD.mirroredUILayout() and self.allow_mirroring then
    if align == "left" then
      align = "right"
    elseif align == "right" then
      align = "left"
    end
  end

  for i, widget in ipairs(self) do
    if align == "center" then
      widget:paintTo(
        bb,
        x + math.floor((size.w - self._offsets[i].x) / 2),
        y + self._offsets[i].y
      )
    elseif align == "left" then
      widget:paintTo(bb, x, y + self._offsets[i].y)
    elseif align == "right" then
      widget:paintTo(
        bb,
        x + size.w - self._offsets[i].x,
        y + self._offsets[i].y
      )
    end
  end
end

function VerticalGroup:clear()
  self:free()
  -- Skip WidgetContainer:clear's free call, we just did that in our own free ;)
  WidgetContainer.clear(self, true)
end

function VerticalGroup:resetLayout()
  self.dimen = nil
  self._offsets = {}
end

function VerticalGroup:free()
  --print("VerticalGroup:free on", self)
  self:resetLayout()
  WidgetContainer.free(self)
end

return VerticalGroup
