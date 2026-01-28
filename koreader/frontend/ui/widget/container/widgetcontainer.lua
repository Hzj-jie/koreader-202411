--[[--
WidgetContainer is a container for one or multiple Widgets. It is the base
class for all the container widgets.

Child widgets are stored in WidgetContainer as conventional array items:

    WidgetContainer:new{
        ChildWidgetFoo:new{},
        ChildWidgetBar:new{},
        ...
    }

It handles event propagation and painting (with different alignments) for its children.
]]

local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")
local logger = require("logger")

local WidgetContainer = Widget:extend({})

function WidgetContainer:getSize()
  if self.dimen and self.dimen.w and self.dimen.h then
    -- fixed size
    return self.dimen
  end
  if self[1] then
    -- return size of first child widget
    self:mergeSize(self[1]:getSize())
    return self.dimen
  end
  -- TODO: Remove, use Widget.getSize(self) instead.
  self:mayMergeWidthAndHeight()
  if self.dimen == nil then
    logger.warn(
      "FixMe: WidgetContainer:getSize() returns an empty Geom. ",
      debug.traceback()
    )
    return Geom:new()
  end
  return self.dimen
end

--[[--
Deletes all child widgets.
]]
function WidgetContainer:clear(skip_free)
  -- HorizontalGroup & VerticalGroup call us after already having called free,
  -- so allow skipping this one ;).
  if not skip_free then
    -- Make sure we free 'em before orphaning them...
    self:free()
  end

  while table.remove(self) do
  end
end

function WidgetContainer:dirtyRegion()
  if self.dirty_dimen then
    return self.dirty_dimen
  end
  if self[1] == nil or self[1].dirty_dimen == nil then
    return Widget.dirtyRegion(self)
  end
  return self[1]:dirtyRegion()
end

function WidgetContainer:paintTo(bb, x, y)
  -- Forward painting duties to our first child widget
  if self[1] == nil then
    return
  end
  if self.skip_paint then
    return
  end

  if not self.dimen then
    self:mergeSize(self[1]:getSize())
  end
  self:mergePosition(x, y)

  if self.align == "top" then
    local contentSize = self[1]:getSize()
    self[1]:paintTo(
      bb,
      x + math.floor((self:getSize().w - contentSize.w) / 2),
      y
    )
  elseif self.align == "bottom" then
    local contentSize = self[1]:getSize()
    self[1]:paintTo(
      bb,
      x + math.floor((self:getSize().w - contentSize.w) / 2),
      y + (self:getSize().h - contentSize.h)
    )
  elseif self.align == "center" then
    local contentSize = self[1]:getSize()
    self[1]:paintTo(
      bb,
      x + math.floor((self:getSize().w - contentSize.w) / 2),
      y + math.floor((self:getSize().h - contentSize.h) / 2)
    )
  elseif self.vertical_align == "center" then
    local contentSize = self[1]:getSize()
    self[1]:paintTo(
      bb,
      x,
      y + math.floor((self:getSize().h - contentSize.h) / 2)
    )
  else
    return self[1]:paintTo(bb, x, y)
  end
end

function WidgetContainer:propagateEvent(event)
  -- Propagate to children
  for _, widget in ipairs(self) do
    if widget:handleEvent(event) then
      -- Stop propagating when an event handler returns true
      return true
    end
  end
  return false
end

--[[--
WidgetContainer will pass event to its children by calling their handleEvent
methods. If no child consumes the event (by returning true), it will try
to react to the event by itself.

@tparam ui.event.Event event
@treturn bool true if event is consumed, otherwise false. A consumed event will
not be sent to other widgets.
]]
function WidgetContainer:handleEvent(event)
  if self:propagateEvent(event) then
    return true
  end
  -- call our own standard event handler
  return Widget.handleEvent(self, event)
end

function WidgetContainer:broadcastEvent(event) --> void
  for _, widget in ipairs(self) do
    widget:broadcastEvent(event)
  end
  Widget.handleEvent(self, event)
end

-- Honor full for TextBoxWidget's benefit...
function WidgetContainer:free(full)
  for _, widget in ipairs(self) do
    if widget.free then
      --print("WidgetContainer: Calling free for widget", debug.getinfo(widget.free, "S").short_src, widget, "from", debug.getinfo(self.free, "S").short_src, self)
      widget:free(full)
    end
  end
end

return WidgetContainer
