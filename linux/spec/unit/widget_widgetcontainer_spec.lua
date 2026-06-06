describe("WidgetContainer component", function()
    local Widget, WidgetContainer, Event

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Widget = require("ui/widget/widget")
        WidgetContainer = require("ui/widget/container/widgetcontainer")
        Event = require("ui/event")
    end)

    it("should propagate handleEvent to children and stop when consumed", function()
        local child1_calls = 0
        local child2_calls = 0
        local container_calls = 0

        local child1 = Widget:new({
            onCustom = function()
                child1_calls = child1_calls + 1
                return true -- consume
            end,
        })
        local child2 = Widget:new({
            onCustom = function()
                child2_calls = child2_calls + 1
                return true
            end,
        })

        local container = WidgetContainer:new({
            child1,
            child2,
            onCustom = function()
                container_calls = container_calls + 1
                return true
            end,
        })

        local res = container:handleEvent(Event:new("Custom"):asUserInput())

        assert.is_true(res)
        assert.is.same(1, child1_calls)
        assert.is.same(0, child2_calls) -- propagation stopped
        assert.is.same(0, container_calls) -- container fallback not called
    end)

    it("should fall back to container event handler if children do not consume", function()
        local child1_calls = 0
        local container_calls = 0

        local child1 = Widget:new({
            onCustom = function()
                child1_calls = child1_calls + 1
                return false -- propagate
            end,
        })

        local container = WidgetContainer:new({
            child1,
            onCustom = function()
                container_calls = container_calls + 1
                return true -- consume at container level
            end,
        })

        local res = container:handleEvent(Event:new("Custom"):asUserInput())

        assert.is_true(res)
        assert.is.same(1, child1_calls)
        assert.is.same(1, container_calls) -- handled by container
    end)

    it("should broadcastEvent to all children and itself", function()
        local child1_calls = 0
        local child2_calls = 0
        local container_calls = 0

        local child1 = Widget:new({
            onCustom = function()
                child1_calls = child1_calls + 1
                return true -- consume (should not stop broadcast)
            end,
        })
        local child2 = Widget:new({
            onCustom = function()
                child2_calls = child2_calls + 1
                return true
            end,
        })

        local container = WidgetContainer:new({
            child1,
            child2,
            onCustom = function()
                container_calls = container_calls + 1
                return true
            end,
        })

        container:broadcastEvent(Event:new("Custom"))

        assert.is.same(1, child1_calls)
        assert.is.same(1, child2_calls) -- still called despite child1 returning true
        assert.is.same(1, container_calls) -- container itself also gets called
    end)
end)
