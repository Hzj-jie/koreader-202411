--[[--
HookContainer allows listeners to register and unregister a hook for speakers to execute.

Unlike the broadcastEvent and sendEvent in UIManager, this implementation does not broadcast the
event to all the widgets and should provide a much better performance, hence the reason of this
implementation.

It's an experimental feature: use with cautions, it can easily pin an object in memory and unblock
GC from recycling the memory.
]]

local HookContainer = {}

function HookContainer:new(name)
    assert(type(name) == "string")
    assert(string.len(name) > 0)
    local o = {
        name = name,
        funcs = {},
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function HookContainer:_assertIsValidFunction(func)
    assert(type(func) == "function" or type(func) == "table")
end

function HookContainer:_assertIsValidFunctionOrNil(func)
    if func == nil then return end
    self:_assertIsValidFunction(func)
end

--- Register a function. Must be called with self.
--- Using this function is extremely dangerous, caller needs to unregister the function ref in the
--- right time.
-- @tparam function func The function to handle the hook. Can only be a function.
function HookContainer:register(func)
    self:_assertIsValidFunction(func)
    table.insert(self.funcs, func)
end

--- Register a widget. Must be called with self.
-- @tparam table widget The widget to handle the hook. Can only be a table with required functions.
function HookContainer:registerWidget(widget)
    assert(type(widget) == "table")
    -- *That* is the function we actually register and need to unregister later, so keep a ref to it...
    local hook_func = function(args)
        local f = widget["on" .. self.name]
        self:_assertIsValidFunction(f)
        f(widget, args)
    end
    self:register(hook_func)
    local original_close_widget = widget.onCloseWidget
    self:_assertIsValidFunctionOrNil(original_close_widget)
    widget.onCloseWidget = function()
        if original_close_widget then original_close_widget(widget) end
        self:unregister(hook_func)
    end
end

--- Unregister a function. Must be called with self.
-- @tparam function func The function to handle the hook. Can only be a function.
-- @treturn boolean Return true if the function is found and removed, otherwise false.
function HookContainer:unregister(func)
    self:_assertIsValidFunction(func)
    for i, f in ipairs(self.funcs) do
        if f == func then
            table.remove(self.funcs, i)
            return true
        end
    end
    return false
end

--- Execute all registered functions. Must be called with self.
-- @param args Any kind of arguments sending to the functions.
-- @treturn number The number of functions have been executed.
function HookContainer:execute(args)
    if #self.funcs == 0 then
        return 0
    end

    for _, f in ipairs(self.funcs) do
        f(args)
    end
    return #self.funcs
end

return HookContainer
