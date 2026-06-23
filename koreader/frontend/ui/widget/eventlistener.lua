--[[--
The EventListener is an interface that handles events. This is the base class
for @{ui.widget.widget|Widget}

EventListeners have a rudimentary event handler/dispatcher that
will call a method "onEventName" for an event with name
"EventName"
]]

local EventListener = {}

function EventListener:extend(subclass_prototype)
  local o = subclass_prototype or {}
  setmetatable(o, self)
  self.__index = self
  return o
end

function EventListener:new(o)
  o = self:extend(o)
  if o.init then
    o:init()
  end
  return o
end

function EventListener:_runEvent(f, event)
  assert(type(f) == "function")
  return f(self, unpack(event.args, 1, event.args.n))
end

--[[--
Invoke handler method for an event.

Handler method name is determined by @{ui.event.Event}'s handler field.
By default, it's `"on"..Event.name`.

Note, anything explicitly calls handleEvent should send in an
Event:asUserInput() / Event:isUserInput(); meanwhile broadcastEvent also uses
the same logic to process the non-user-input events.
Note, explicitly calling this function is less common, most of the user inputs
should come from UIManager:userInput(). broadcastEvent is usually the right
choice in most of the cases, especially when the return value of the function
call is ignored.

@tparam ui.event.Event event
@treturn bool return true if event is consumed successfully.
]]
function EventListener:handleEvent(event)
  if self[event.handler] == nil then
    return self:isShownModal() and event:isUserInput()
  end
  if type(self[event.handler]) == "function" then
    local r = self:_runEvent(self[event.handler], event)
    if r then
      return true
    end
  else
    assert(type(self[event.handler]) == "table")
    local r = false
    for _, v in ipairs(self[event.handler]) do
      local res = self:_runEvent(v, event)
      if res then
        r = true
      end
    end
    if r then
      return true
    end
  end

  return not event:isUserInput() or self:isShownModal()
end

-- Checks if the widget belongs in the topmost visual layer (above standard widgets).
-- Note: Multiple always-on-top widgets can coexist in the stack; they will be
-- layered sequentially relative to one another in the order they are shown.
function EventListener:isAlwaysOnTop()
  return self.modal == true
end

function EventListener:isShownModal()
  -- Coerce to boolean explicitly to avoid returning nil if self.modal is undefined.
  return (self.modal == true) and require("ui/uimanager"):isWindowWidget(self)
end

function EventListener:broadcastEvent(event) --> void
  self:handleEvent(event)
end

return EventListener
