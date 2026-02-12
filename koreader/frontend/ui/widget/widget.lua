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
  if self:isShown() then
    -- Otherwise the widget hasn't been shown yet and will be paintTo later.
    require("ui/uimanager"):scheduleWidgetRepaint(self)
  end
end

function Widget:scheduleRefresh() -- final
  if self:isShown() then
    -- Otherwise the widget hasn't been shown yet and will be paintTo later.
    require("ui/uimanager"):scheduleRefresh(
      self:refreshMode(),
      self:dirtyRegion()
    )
  end
end

function Widget:isShown() -- final
  return self:window() ~= nil
end

-- Get the show(widget) of current widget, using this function should be careful
-- due to it's slowness.
function Widget:showParent() -- final
  local window = self:window()
  return window ~= nil and window.widget or nil
end

function Widget:ui_depth() -- final
  -- Ensure the self._ui_depth is calculated.
  self:window()
  -- But it's still possible to return a nil.
  return self._ui_depth
end

function Widget:_window() -- final
  local UIManager = require("ui/uimanager")
  -- A fast loop to avoid dfs.
  for w in UIManager:topdown_windows_iter() do
    if w.widget == self then
      self._ui_depth = 1
      return w
    end
  end

  for w in UIManager:topdown_windows_iter() do
    local r, d = require("util").arrayDfSearch(w.widget, self)
    if r then
      self._ui_depth = d
      return w
    end
  end

  -- This is unfortunate, it would trigger the recalculation each time.
  return nil
end

-- Get the window of current widget, use this function should be careful due
-- to it's slowness.
function Widget:window() -- final
  if self._window_ref == nil then
    self._window_ref = self:_window()
  end
  return self._window_ref
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
