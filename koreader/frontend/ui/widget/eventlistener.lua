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

@tparam ui.event.Event event
@treturn bool return true if event is consumed successfully.
]]
function EventListener:handleEvent(event)
  if self[event.handler] then
    --print("EventListener:handleEvent:", event.handler, "handled by", debug.getinfo(self[event.handler], "S").short_src, self)
    local r = false
    if type(self[event.handler]) == "function" then
      r = self:_runEvent(self[event.handler], event)
    else
      assert(type(self[event.handler]) == "table")
      for _, v in ipairs(self[event.handler]) do
        r = r or self:_runEvent(v, event)
      end
    end
    return r
  end
end

function EventListener:broadcastEvent(event) --> void
  self:handleEvent(event)
end

return EventListener
