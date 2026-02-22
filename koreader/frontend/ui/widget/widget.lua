--[[--
This is a generic Widget interface, which is the base class for all other widgets.

Widgets can be queried about their size and can be painted on screen.
that's it for now. Probably we need something more elaborate
later.

If the table that was given to us as parameter has an "init"
method, it will be called. use this to set _instance_ variables
rather than class variables.
]]

local EventListener = require("ui/widget/eventlistener")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")

--- Widget base class
-- @table Widget
local Widget = EventListener:extend({})

--[[--
Use this method to define a widget subclass that's inherited from a base class widget.
It only setups the metatable (or prototype chain) and will not initiate a real instance, i.e. call self:init().

@tparam table subclass
@treturn Widget
]]
function Widget:extend(subclass_prototype)
  local o = subclass_prototype or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

--[[--
Use this method to initiate an instance of a class.
Do NOT use it for class definitions because it also calls self:init().

@tparam table o
@treturn Widget
]]
function Widget:new(o)
  o = self:extend(o)
  -- Both o._init and o.init are called on object creation.
  -- But o._init is used for base widget initialization (basic components used to build other widgets).
  -- While o.init is for higher level widgets, for example Menu.
  if o._init then
    o:_init()
  end
  if o.init then
    o:init()
  end
  return o
end

--[[
FIXME: Enable this doc section once we've verified all self.dimen are Geom objects
       so we can return self.dimen:copy() instead of a live ref.

Return size of the widget.

Most of the implementations shouldn't override this function, but setting the
self.dimen instead.

@treturn ui.geometry.Geom
--]]
function Widget:getSize()
  self:mayMergeWidthAndHeight()
  assert(self.dimen ~= nil)
  return self.dimen
end

-- TODO: This function is for WidgetContainer and should be removed after being
-- migrated. Investigate the use of this function, e.g. if Widget:getSize() ever
-- reachs the if condition.
function Widget:mayMergeWidthAndHeight()
  if self.width ~= nil or self.height ~= nil then
    self:mergeSize(self.width or 0, self.height or 0)
  end
end

function Widget:mergeSize(w, h)
  if type(w) == "table" then
    assert(h == nil)
    h = w.h
    w = w.w
  end
  assert(w ~= nil)
  assert(h ~= nil)
  if self.dimen ~= nil then
    self.dimen.w = w
    self.dimen.h = h
  else
    self.dimen = Geom:new({ w = w, h = h })
  end
end

function Widget:mergePosition(x, y)
  if self.dimen ~= nil then
    -- Keep the same reference.
    self.dimen.x = x
    self.dimen.y = y
  else
    self.dimen = Geom:new({ x = x, y = y })
  end
end

--[[--
Paint widget to a BlitBuffer.

@tparam BlitBuffer bb BlitBuffer to paint to.
If it's the screen BlitBuffer, then widget will show up on screen refresh.
@int x x offset within the BlitBuffer
@int y y offset within the BlitBuffer
]]
function Widget:paintTo(bb, x, y) end

function Widget:refreshMode()
  return self._refresh_mode or "ui"
end

-- Similar to the :getSize(), most of the implementations should set
-- self.dirty_dimen instead of overriding.
function Widget:dirtyRegion()
  return self.dirty_dimen or self:getSize()
end

function Widget:scheduleRepaint() -- final
  if self:_isInWindowStack() then
    -- Otherwise the widget hasn't been shown yet and will be paintTo later.
    require("ui/uimanager"):scheduleWidgetRepaint(self)
  end
end

function Widget:scheduleRefresh() -- final
  if self:_isInWindowStack() then
    -- Otherwise the widget hasn't been shown yet and will be paintTo later.
    require("ui/uimanager"):scheduleRefresh(
      self:refreshMode(),
      self:dirtyRegion()
    )
  end
end

-- Use with caution, UIManager:setDirty is a deprecated function.
function Widget:setDirty(...) -- final
  if self:_isInWindowStack() then
    require("ui/uimanager"):setDirty(self, ...)
  end
end

-- This function doesn't really mean the Widget has been painted, but it may be
-- in the queue of being painted immediately. UIManager uses it as a very quick
-- test to ensure it won't schedule a repaint on anything which isn't in the
-- window stack yet, i.e. will be painted in random places and / or cover other
-- elements.
function Widget:_isInWindowStack() -- final
  return self:window() ~= nil
end

-- Get the show(widget) of current widget, using this function should be careful
-- due to it's slowness.
function Widget:showParent() -- final
  local window = self:window()
  return window ~= nil and window.widget or nil
end

-- Returns the z-index in the window, not the entire ui stack.
function Widget:window_z_index() -- final
  -- Ensure the self._window_z_index is calculated.
  if self:window() == nil then
    -- But it's still possible to return a nil if 1) window is closed, 2) widget
    -- hasn't been shown yet.
    self._window_z_index = nil
  end
  return self._window_z_index
end

function Widget:_window() -- final
  local UIManager = require("ui/uimanager")
  -- A fast loop to avoid dfs.
  for w in UIManager:topdown_windows_iter() do
    if w.widget == self then
      self._window_z_index = 1
      return w
    end
  end

  for w in UIManager:topdown_windows_iter() do
    local r, d = require("util").arrayDfSearch(w.widget, self)
    if r then
      self._window_z_index = d
      return w
    end
  end

  -- This is unfortunate, it would trigger the recalculation each time.
  return nil
end

-- Get the window of current widget, use this function should be careful due
-- to it's slowness.
function Widget:window() -- final
  -- TODO: Caching the self:_window() result breaks Terminal.
  return self:_window()
end

function Widget:myRange(ges)
  return GestureRange:new({
    ges = ges,
    range = function()
      return self:getSize()
    end,
  })
end

return Widget
