--[[--
A layout widget that puts objects besides each other.
--]]

local BD = require("ui/bidi")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")

local HorizontalGroup = WidgetContainer:extend({
  align = "center",
  allow_mirroring = true,
})

function HorizontalGroup:getSize()
  if self._offsets == nil or self.dimen == nil then
    self:mergeSize(0, 0)
    local _mirroredUI = BD.mirroredUILayout()
    self._offsets = {}
    if _mirroredUI and self.allow_mirroring then
      util.arrayReverse(self)
    end
    for i, widget in ipairs(self) do
      local w_size = widget:getSize()
      self._offsets[i] = {
        x = self.dimen.w,
        y = w_size.h,
      }
      self.dimen.w = self.dimen.w + w_size.w
      if w_size.h > self.dimen.h then
        self.dimen.h = w_size.h
      end
    end
    if _mirroredUI and self.allow_mirroring then
      util.arrayReverse(self)
    end
  end
  assert(self.dimen ~= nil)
  return self.dimen
end

function HorizontalGroup:paintTo(bb, x, y)
  local size = self:getSize()
  self:mergePosition(x, y)
  local _mirroredUI = BD.mirroredUILayout()

  if _mirroredUI and self.allow_mirroring then
    util.arrayReverse(self)
  end
  for i, widget in ipairs(self) do
    if self.align == "center" then
      widget:paintTo(
        bb,
        x + self._offsets[i].x,
        y + math.floor((size.h - self._offsets[i].y) / 2)
      )
    elseif self.align == "top" then
      widget:paintTo(bb, x + self._offsets[i].x, y)
    elseif self.align == "bottom" then
      widget:paintTo(
        bb,
        x + self._offsets[i].x,
        y + size.h - self._offsets[i].y
      )
    else
      io.stderr:write("[!] invalid alignment for HorizontalGroup: ", self.align)
    end
  end
  if _mirroredUI and self.allow_mirroring then
    util.arrayReverse(self)
  end
end

function HorizontalGroup:clear()
  self:free()
  -- Skip WidgetContainer:clear's free call, we just did that in our own free ;)
  WidgetContainer.clear(self, true)
end

function HorizontalGroup:resetLayout()
  self.dimen = nil
  self._offsets = {}
end

function HorizontalGroup:free()
  --print("HorizontalGroup:free on", self)
  self:resetLayout()
  WidgetContainer.free(self)
end

return HorizontalGroup
