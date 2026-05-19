local Dispatcher
local UIManager
local Event

describe("dispatcher", function()
    local original_user_input
    local original_broadcast_event
    local original_readerui
    local captured_inputs = {}
    local captured_broadcasts = {}

    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        Event = require("ui/event")
        Dispatcher = require("dispatcher")
        original_user_input = UIManager.userInput
        original_broadcast_event = UIManager.broadcastEvent
        original_readerui = package.loaded["apps/reader/readerui"]

        UIManager.userInput = function(_, event)
            if type(event) == "string" then
                event = Event:new(event)
            end
            table.insert(captured_inputs, event)
        end

        UIManager.broadcastEvent = function(_, event)
            if type(event) == "string" then
                event = Event:new(event)
            end
            table.insert(captured_broadcasts, event)
        end
    end)

    teardown(function()
        UIManager.userInput = original_user_input
        UIManager.broadcastEvent = original_broadcast_event
        package.loaded["apps/reader/readerui"] = original_readerui
    end)

    before_each(function()
        captured_inputs = {}
        captured_broadcasts = {}
    end)

    describe("registerAction and removeAction", function()
        after_each(function()
            Dispatcher:removeAction("test_action")
        end)

        it("registers and removes custom action successfully", function()
            package.loaded["apps/reader/readerui"] = {
                instance = {
                    paging = true
                }
            }

            local action_def = {
                category = "none",
                event = "MyCustomEvent",
                reader = true,
            }

            -- Should register custom action
            assert.is_true(Dispatcher:registerAction("test_action", action_def))

            -- Should trigger the event upon execution
            Dispatcher:execute({ test_action = true })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onMyCustomEvent", captured_inputs[1].handler)

            -- Should remove custom action
            assert.is_true(Dispatcher:removeAction("test_action"))

            -- Execution should no longer trigger the event
            captured_inputs = {}
            Dispatcher:execute({ test_action = true })
            assert.are.equal(0, #captured_inputs)
        end)
    end)

    describe("isActionEnabled", function()
        it("handles condition-based activation", function()
            assert.is_true(Dispatcher:isActionEnabled({}))
            assert.is_true(Dispatcher:isActionEnabled({ condition = true }))
            assert.is_false(Dispatcher:isActionEnabled({ condition = false }))
        end)

        it("handles FileManager context when reader context is missing", function()
            package.loaded["apps/reader/readerui"] = {
                instance = nil
            }

            -- Should be disabled if it's reader only
            assert.is_false(Dispatcher:isActionEnabled({ reader = true }))
            assert.is_false(Dispatcher:isActionEnabled({ paging = true }))
            assert.is_false(Dispatcher:isActionEnabled({ rolling = true }))

            -- Should be enabled if not restricted or explicitly filemanager
            assert.is_true(Dispatcher:isActionEnabled({ filemanager = true }))
            assert.is_true(Dispatcher:isActionEnabled({ filemanager = true, reader = true }))
        end)

        it("handles Paging Reader context", function()
            package.loaded["apps/reader/readerui"] = {
                instance = {
                    paging = true
                }
            }

            assert.is_true(Dispatcher:isActionEnabled({ reader = true }))
            assert.is_true(Dispatcher:isActionEnabled({ paging = true }))
            assert.is_false(Dispatcher:isActionEnabled({ rolling = true }))
        end)

        it("handles Rolling Reader context", function()
            package.loaded["apps/reader/readerui"] = {
                instance = {
                    paging = false
                }
            }

            assert.is_true(Dispatcher:isActionEnabled({ reader = true }))
            assert.is_false(Dispatcher:isActionEnabled({ paging = true }))
            assert.is_true(Dispatcher:isActionEnabled({ rolling = true }))
        end)
    end)

    describe("execute categories", function()
        setup(function()
            package.loaded["apps/reader/readerui"] = {
                instance = {
                    paging = true
                }
            }
        end)

        after_each(function()
            Dispatcher:removeAction("test_action")
        end)

        it("handles category 'none' without arguments", function()
            Dispatcher:registerAction("test_action", {
                category = "none",
                event = "EventNone",
                reader = true,
            })

            Dispatcher:execute({ test_action = true })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventNone", captured_inputs[1].handler)
            assert.are.equal(0, captured_inputs[1].args.n)
        end)

        it("handles category 'none' with static argument", function()
            Dispatcher:registerAction("test_action", {
                category = "none",
                event = "EventNoneWithArg",
                arg = "static_value",
                reader = true,
            })

            local exec_props = { gesture = "some_gesture" }
            Dispatcher:execute({ test_action = true }, exec_props)
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventNoneWithArg", captured_inputs[1].handler)
            assert.are.equal(2, captured_inputs[1].args.n)
            assert.are.equal("static_value", captured_inputs[1].args[1])
            assert.are.same(exec_props, captured_inputs[1].args[2])
        end)

        it("handles category 'absolutenumber'", function()
            Dispatcher:registerAction("test_action", {
                category = "absolutenumber",
                event = "EventAbsoluteNumber",
                reader = true,
            })

            Dispatcher:execute({ test_action = 42 })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventAbsoluteNumber", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal(42, captured_inputs[1].args[1])
        end)

        it("handles category 'string'", function()
            Dispatcher:registerAction("test_action", {
                category = "string",
                event = "EventString",
                reader = true,
            })

            Dispatcher:execute({ test_action = "value_str" })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventString", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal("value_str", captured_inputs[1].args[1])
        end)

        it("handles category 'arg' with gesture", function()
            Dispatcher:registerAction("test_action", {
                category = "arg",
                event = "EventArg",
                arg = "default_arg",
                reader = true,
            })

            Dispatcher:execute({ test_action = true }, { gesture = "swipe_down" })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventArg", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal("swipe_down", captured_inputs[1].args[1])
        end)

        it("handles category 'arg' without gesture", function()
            Dispatcher:registerAction("test_action", {
                category = "arg",
                event = "EventArg",
                arg = "default_arg",
                reader = true,
            })

            Dispatcher:execute({ test_action = true })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventArg", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal("default_arg", captured_inputs[1].args[1])
        end)

        it("handles category 'incrementalnumber' with value", function()
            Dispatcher:registerAction("test_action", {
                category = "incrementalnumber",
                event = "EventIncNum",
                reader = true,
            })

            Dispatcher:execute({ test_action = 3 })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventIncNum", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal(3, captured_inputs[1].args[1])
        end)

        it("handles category 'incrementalnumber' with gesture", function()
            Dispatcher:registerAction("test_action", {
                category = "incrementalnumber",
                event = "EventIncNum",
                reader = true,
            })

            Dispatcher:execute({ test_action = 0 }, { gesture = "swipe_left" })
            assert.are.equal(1, #captured_inputs)
            assert.are.equal("onEventIncNum", captured_inputs[1].handler)
            assert.are.equal(1, captured_inputs[1].args.n)
            assert.are.equal("swipe_left", captured_inputs[1].args[1])
        end)

        it("handles batched updates for multiple actions", function()
            Dispatcher:registerAction("test_action1", {
                category = "none",
                event = "Event1",
                reader = true,
            })
            Dispatcher:registerAction("test_action2", {
                category = "none",
                event = "Event2",
                reader = true,
            })

            -- We use ordered settings list or simple settings map
            -- If we pass simple map, order is arbitrary, but both should be triggered
            Dispatcher:execute({ test_action1 = true, test_action2 = true })

            Dispatcher:removeAction("test_action1")
            Dispatcher:removeAction("test_action2")

            assert.are.equal(2, #captured_inputs)
            local event_names = { captured_inputs[1].handler, captured_inputs[2].handler }
            table.sort(event_names)
            assert.are.same({ "onEvent1", "onEvent2" }, event_names)

            -- Should also broadcast BatchedUpdate and BatchedUpdateDone
            assert.are.equal(2, #captured_broadcasts)
            assert.are.equal("onBatchedUpdate", captured_broadcasts[1].handler)
            assert.are.equal("onBatchedUpdateDone", captured_broadcasts[2].handler)
        end)
    end)
end)
