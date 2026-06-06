describe("EventListener class", function()
    local EventListener, Event

    setup(function()
        require("commonrequire")
        EventListener = require("ui/widget/eventlistener")
        Event = require("ui/event")
    end)

    it("should route event to string handler function and unpack args", function()
        local received_arg1, received_arg2 = nil, nil
        local el = EventListener:new({
            onMyCustomEvent = function(self, arg1, arg2)
                received_arg1 = arg1
                received_arg2 = arg2
                return true
            end
        })

        local ev = Event:new("MyCustomEvent", "hello", "world")
        local res = el:handleEvent(ev)

        assert.is_true(res)
        assert.is.same("hello", received_arg1)
        assert.is.same("world", received_arg2)
    end)

    it("should route event to table of handler functions", function()
        local call_count = 0
        local el = EventListener:new({
            onMyCustomEvent = {
                function(self, event)
                    call_count = call_count + 1
                    return false
                end,
                function(self, event)
                    call_count = call_count + 1
                    return true
                end,
            }
        })

        local ev = Event:new("MyCustomEvent")
        local res = el:handleEvent(ev)

        assert.is_true(res)
        assert.is.same(2, call_count)
    end)

    it("should return false if no handler is registered", function()
        local el = EventListener:new({})
        local ev = Event:new("MyCustomEvent")
        local res = el:handleEvent(ev)

        assert.is_false(res)
    end)

    it("should return true for programmatic event even if handler returns false", function()
        local el = EventListener:new({
            onMyCustomEvent = function(self, event)
                return false
            end
        })

        local ev = Event:new("MyCustomEvent") -- programmatic event by default
        assert.is_false(ev:isUserInput())

        local res = el:handleEvent(ev)
        assert.is_true(res) -- Overridden to true by EventListener on master!
    end)

    it("should respect handler return status for user input event", function()
        local el = EventListener:new({
            onMyCustomEvent = function(self, event)
                return false
            end
        })

        local ev = Event:new("MyCustomEvent"):asUserInput()
        assert.is_true(ev:isUserInput())

        local res = el:handleEvent(ev)
        assert.is_false(res) -- Preserves false for user input!
    end)
end)
