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

@treturn ui.geometry.Geom
--]]
function Widget:getSize()
  if self.width ~= nil or self.height ~= nil then
    self:mergeSize({ w = self.width or 0, h = self.height or 0 })
  end
  assert(self.dimen ~= nil)
  return self.dimen
end

function Widget:mergeSize(w, h)
  if type(w) == "table" then
    assert(h == nil)
    h = w.h
    w = w.w
  end
  if self.dimen ~= nil then
    self.dimen.w = w
    self.dimen.h = h
  else
    self.dimen = Geom:new({ x = 0, y = 0, w = w, h = h })
  end
end

function Widget:mergePosition(x, y)
  if self.dimen ~= nil then
    -- Keep the same reference.
    self.dimen.x = x
    self.dimen.y = y
  else
    self.dimen = Geom:new({ x = x, y = y, w = 0, h = 0 })
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

function Widget:dirtyRegion()
  return self.dirty_dimen or self.dimen or require("device").screen:getSize()
end

-- Get the show(widget) of current widget, using this function should be careful
-- due to it's slowness.
function Widget:showParent()
  local window = self:window()
  return window ~= nil and window.widget or nil
end

-- Get the window of current widget, use this function should be careful due
-- to it's slowness.
function Widget:window()
  local UIManager = require("ui/uimanager")
  -- A fast loop to avoid dfs.
  for w in UIManager:topdown_windows_iter() do
    if w.widget == self then
      return w
    end
  end

  for w in UIManager:topdown_windows_iter() do
    if require("util").arrayDfSearch(w.widget, self) then
      return w
    end
  end
  return nil
end

return Widget
