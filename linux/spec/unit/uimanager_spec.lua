describe("UIManager spec", function()
    local time, UIManager, Widget, MockTime
    local now, wait_until
    local noop = function() end

    setup(function()
        require("commonrequire")
        MockTime = require("mock_time")
        MockTime:install()
        time = require("ui/time")
        UIManager = require("ui/uimanager")
        Widget = require("ui/widget/widget"):extend({
          dimen = require("ui/geometry"):new({ x = 0, y = 0, w = 100, h = 200 })
        })
    end)

    teardown(function()
        MockTime:uninstall()
    end)

    it("should consume due tasks", function()
        now = time.monotonic()
        local future = now + time.s(60000)
        local future2 = future + time.s(5)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future2, action = noop, args = {} },
            { time = future, action = noop, args = {} },
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        UIManager:_checkTasks()
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same(future, UIManager._task_queue[2].time)
        assert.are.same(future2, UIManager._task_queue[1].time)
    end)

    it("should calculate wait_until properly in checkTasks routine", function()
        now = time.monotonic()
        local future_time = now + time.s(60000)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future_time, action = noop, args = {} },
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        wait_until, now = UIManager:_checkTasks()
        assert.are.same(future_time, wait_until)
    end)

    it("should return nil wait_until properly in checkTasks routine", function()
        now = time.monotonic()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = noop, args = {} },
            { time = now - time.us(5), action = noop, args = {} },
            { time = now - time.s(10), action = noop, args = {} },
        }

        wait_until, now = UIManager:_checkTasks()
        assert.are.same(nil, wait_until)
    end)

    it("should insert new task properly in empty task queue", function()
        now = time.monotonic()
        UIManager:quit()
        assert.are.same(0, #UIManager._task_queue)
        UIManager:scheduleIn(50, 'foo')
        assert.are.same(1, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[1].action)
    end)

    it("should insert new task properly in single task queue", function()
        now = time.monotonic()
        local future_time = now + time.s(10000)
        UIManager:quit()
        UIManager._task_queue = {
            { time = future_time, action = '1', args = {} },
        }

        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'quz')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('quz', UIManager._task_queue[2].action)

        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '1', args = {} },
        }

        assert.are.same(1, #UIManager._task_queue)
        UIManager:scheduleIn(150, 'foo')
        assert.are.same(2, #UIManager._task_queue)
        assert.are.same('foo', UIManager._task_queue[1].action)
        UIManager:scheduleIn(155, 'bar')
        assert.are.same(3, #UIManager._task_queue)
        assert.are.same('bar', UIManager._task_queue[1].action)
    end)

    it("should insert new task in descendant order", function()
        now = time.monotonic()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '3', args = {} },
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
        }

        -- insert into the tail slot
        UIManager:scheduleIn(10, 'foo')
        assert.are.same('foo', UIManager._task_queue[1].action)
        -- insert into the second slot
        UIManager:schedule(now - time.s(5), 'bar')
        assert.are.same('bar', UIManager._task_queue[4].action)
        -- insert into the head slot
        UIManager:schedule(now - time.s(15), 'baz')
        assert.are.same('baz', UIManager._task_queue[6].action)
        -- insert into the last second slot
        UIManager:scheduleIn(5, 'qux')
        assert.are.same('qux', UIManager._task_queue[2].action)
        -- insert into the middle slot
        UIManager:schedule(now - time.us(1), 'quux')
        assert.are.same('quux', UIManager._task_queue[4].action)
    end)

    it("should insert new tasks with same times before existing tasks", function()
        now = time.monotonic()
        UIManager:quit()

        -- insert task "5s" between "now" and "10s"
        UIManager:schedule(now, "now");
        assert.are.same("now", UIManager._task_queue[1].action)
        UIManager:schedule(now + time.s(10), "10s");
        assert.are.same("10s", UIManager._task_queue[1].action)
        UIManager:schedule(now + time.s(5), "5s");
        assert.are.same("5s", UIManager._task_queue[2].action)

        -- insert task in place of "10s", as it'll expire shortly after "10s"
        MockTime:increase(0.001)
        UIManager:scheduleIn(10, 'foo') -- is a bit later than "10s", as time.monotonic() is used internally
        assert.are.same('foo', UIManager._task_queue[1].action)

        -- insert task in place of "10s", which was just shifted by foo
        UIManager:schedule(now + time.s(10), 'bar')
        assert.are.same('bar', UIManager._task_queue[2].action)

        -- insert task in place of "bar"
        UIManager:schedule(now + time.s(10), 'baz')
        assert.are.same('baz', UIManager._task_queue[2].action)

        -- insert task in place of "5s"
        UIManager:schedule(now + time.s(5), 'nix')
        assert.are.same('nix', UIManager._task_queue[5].action)
        -- "barba" replaces "nix"
        UIManager:scheduleIn(5, 'barba') -- is a bit later than "5s", as time.monotonic() is used internally
        assert.are.same('barba', UIManager._task_queue[5].action)

        -- "mama is scheduled now and as such inserted in "now"'s place
        UIManager:schedule(now, 'mama')
        assert.are.same('mama', UIManager._task_queue[8].action)

        -- "papa" is shortly after "now", so inserted in its place
        -- NOTE: For the same reason as above, test this last, as time.monotonic may not have moved...
        UIManager:nextTick('papa') -- is a bit later than "now"
        assert.are.same('papa', UIManager._task_queue[8].action)

        -- "letta" is shortly after "papa", so inserted in its place
        UIManager:tickAfterNext('letta')
        assert.are.same("function", type(UIManager._task_queue[8].action))
    end)

    it("should unschedule all the tasks with the same action", function()
        now = time.monotonic()
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = '3', args = {} },
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.us(6), action = '3', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
            { time = now - time.s(15), action = '3', args = {} },
        }

        -- insert into the tail slot
        UIManager:unschedule('3')
        assert.are.same({
            { time = now - time.us(5), action = '2', args = {} },
            { time = now - time.s(10), action = '1', args = {} },
        }, UIManager._task_queue)
    end)

    it("should not have race between unschedule and _checkTasks", function()
        now = time.monotonic()
        local run_count = 0
        local task_to_remove = function()
            run_count = run_count + 1
        end
        UIManager:quit()
        UIManager._task_queue = {
            { time = now, action = task_to_remove, args = {} }, -- this will be removed
            { time = now - time.us(5), action = task_to_remove, args = {} }, -- this will be removed
            {
                time = now - time.s(10),
                action = function() -- this will be called, too
                    run_count = run_count + 1
                    UIManager:unschedule(task_to_remove)
                end,
                args = {},
            },
            { time = now - time.s(15), action = task_to_remove, args = {} }, -- this will be called
        }

        UIManager:_checkTasks()
        assert.are.same(2, run_count)
    end)

    it("should clear _task_queue_dirty bit before looping", function()
        UIManager:quit()
        assert.is.not_true(UIManager._task_queue_dirty)
        UIManager:nextTick(function() UIManager:nextTick(noop) end)
        UIManager:_checkTasks()
        assert.is_true(UIManager._task_queue_dirty)
    end)

    describe("modal widgets", function()
        it("should insert modal widget on top", function()
            -- first modal widget
            UIManager:show(Widget:new({
                x_prefix_test_number = 1,
                modal = true
            }))
            -- regular widget, should go under modal widget
            UIManager:show(Widget:new({
                x_prefix_test_number = 2,
                modal = nil
            }))

            assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
            assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
        end)
        it("should insert second modal widget on top of first modal widget", function()
            UIManager:show(Widget:new({
                x_prefix_test_number = 3,
                modal = true
            }))

            assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
            assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
            assert.equals(3, UIManager._window_stack[3].widget.x_prefix_test_number)
        end)
    end)

    it("should check active widgets in order", function()
        local call_signals = {false, false, false}
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        call_signals[1] = true
                        return true
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[2] = true
                        return true
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[3] = true
                        return true
                    end
                }
            },
            {widget = {handleEvent = function()end}},
        }

        UIManager:userInput("foo")
        assert.falsy(call_signals[1])
        assert.falsy(call_signals[2])
        assert.truthy(call_signals[3])
    end)

    it("should handle stack change when checking for active widgets", function()
        -- scenario 1: 2nd widget removes the 3rd widget in the stack
        local call_signals = {0, 0, 0}
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        call_signals[1] = call_signals[1] + 1
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[2] = call_signals[2] + 1
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[3] = call_signals[3] + 1
                        table.remove(UIManager._window_stack, 2)
                    end
                }
            },
            {widget = {handleEvent = function()end}},
        }

        UIManager:userInput("foo")
        assert.is.same(call_signals[1], 1)
        assert.is.same(call_signals[2], 0)
        assert.is.same(call_signals[3], 1)

        -- scenario 2: top widget removes itself
        call_signals = {0, 0, 0}
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        call_signals[1] = call_signals[1] + 1
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[2] = call_signals[2] + 1
                    end
                }
            },
            {
                widget = {
                    handleEvent = function()
                        call_signals[3] = call_signals[3] + 1
                        table.remove(UIManager._window_stack, 3)
                    end
                }
            },
        }

        UIManager:userInput("foo")
        assert.is.same(1, call_signals[1])
        assert.is.same(1, call_signals[2])
        assert.is.same(1, call_signals[3])
    end)

    it("should allow events to propagate through toast widgets", function()
        local call_signals = {0, 0}
        UIManager._window_stack = {
            {
                widget = {
                    handleEvent = function()
                        call_signals[1] = call_signals[1] + 1
                    end
                }
            },
            {
                widget = {
                    toast = true,
                    handleEvent = function()
                        call_signals[2] = call_signals[2] + 1
                    end
                }
            },
        }

        UIManager:userInput("foo")
        assert.is.same(1, call_signals[1])
        assert.is.same(1, call_signals[2])
    end)

    it("should handle stack change when broadcasting events", function()
        UIManager._window_stack = {
            {
                widget = Widget:new({
                    handleEvent = function()
                        UIManager._window_stack[1] = nil
                    end
                })
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(#UIManager._window_stack, 0)

        -- Remember that the stack is processed top to bottom!
        -- Test making a hole in the middle of the stack.
        UIManager._window_stack = {
            {
                widget = Widget:new({
                    handleEvent = function()
                        assert.truthy(true)
                    end
                })
            },
            {
                widget = Widget:new({
                    handleEvent = function()
                        assert.falsy(true)
                    end
                })
            },
            {
                widget = Widget:new({
                    handleEvent = function()
                        assert.falsy(true)
                    end
                })
            },
            {
                widget = Widget:new({
                    handleEvent = function()
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
                        table.remove(UIManager._window_stack, #UIManager._window_stack - 1)
                    end
                })
            },
            {
                widget = Widget:new({
                    handleEvent = function()
                        assert.truthy(true)
                    end
                })
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(2, #UIManager._window_stack)

        -- Test inserting a new widget in the stack
        local new_widget = {
            widget = Widget:new({
                handleEvent = function()
                    assert.truthy(true)
                end
            })
        }
        UIManager._window_stack = {
            {
                widget = Widget:new({
                    handleEvent = function()
                        table.insert(UIManager._window_stack, new_widget)
                    end
                })
            },
            {
                widget = Widget:new({
                    handleEvent = function()
                        assert.truthy(true)
                    end
                })
            },
        }
        UIManager:broadcastEvent("foo")
        assert.is.same(3, #UIManager._window_stack)
    end)

    it("should handle stack change when closing widgets", function()
        local widget_1 = Widget:new()
        local widget_2  = Widget:new({
            handleEvent = function()
                UIManager:close(widget_1)
            end
        })
        local widget_3 = Widget:new()
        UIManager._window_stack = {
            {x = 0, y = 0, widget = widget_1},
            {x = 0, y = 0, widget = widget_2},
            {x = 0, y = 0, widget = widget_3},
        }
        UIManager:close(widget_2)

        assert.is.same(1, #UIManager._window_stack)
        assert.is.same(widget_3, UIManager._window_stack[1].widget)
    end)

    describe("integration of UIManager and EventListener", function()
        before_each(function()
            UIManager._window_stack = {}
        end)

        after_each(function()
            UIManager._window_stack = {}
        end)

        it("should test event propagation with non-modal widgets", function()
            local base_calls = 0
            local overlay_calls = 0

            local base_view = Widget:new({
                onTap = function()
                    base_calls = base_calls + 1
                    return true
                end
            })
            local overlay = Widget:new({
                onTap = function()
                    overlay_calls = overlay_calls + 1
                    return false -- propagate
                end
            })

            UIManager:show(base_view)
            UIManager:show(overlay)

            local Event = require("ui/event")
            local tap_event = Event:new("Tap"):asUserInput()

            UIManager:userInput(tap_event)

            -- Under a consistent non-modal model, propagation reaches the base view
            assert.is.same(1, base_calls)
            assert.is.same(1, overlay_calls)
        end)

        it("should block event propagation if overlay is modal", function()
            local base_calls = 0
            local overlay_calls = 0

            local base_view = Widget:new({
                onTap = function()
                    base_calls = base_calls + 1
                    return true
                end
            })
            local overlay = Widget:new({
                modal = true,
                onTap = function()
                    overlay_calls = overlay_calls + 1
                    return false -- propagate
                end
            })

            UIManager:show(base_view)
            UIManager:show(overlay)

            local Event = require("ui/event")
            local tap_event = Event:new("Tap"):asUserInput()

            UIManager:userInput(tap_event)

            -- Modal overlay consumes user inputs, so propagation stops
            assert.is.same(0, base_calls)
            assert.is.same(1, overlay_calls)
        end)

        it("should propagate events to base view if overlay is toast", function()
            local base_calls = 0
            local overlay_calls = 0

            local base_view = Widget:new({
                onTap = function()
                    base_calls = base_calls + 1
                    return true
                end
            })
            local overlay = Widget:new({
                toast = true,
                onTap = function()
                    overlay_calls = overlay_calls + 1
                    return false -- propagate
                end
            })

            UIManager:show(base_view)
            UIManager:show(overlay)

            local Event = require("ui/event")
            local tap_event = Event:new("Tap"):asUserInput()

            UIManager:userInput(tap_event)

            -- Toast overlay is non-blocking, so propagation reaches base view
            assert.is.same(1, base_calls)
            assert.is.same(1, overlay_calls)
        end)

        it("should allow parent menu to receive events when child menu is non-modal", function()
            local parent_calls = 0
            local child_calls = 0

            local base_view = Widget:new()

            -- TouchMenu (parent)
            local parent_menu = Widget:new({
                onTap = function()
                    parent_calls = parent_calls + 1
                    return true
                end
            })

            -- Menu (child dropdown)
            local child_menu = Widget:new({
                onTap = function()
                    child_calls = child_calls + 1
                    return false -- propagate to parent
                end
            })

            UIManager:show(base_view)
            UIManager:show(parent_menu)
            UIManager:show(child_menu)

            local Event = require("ui/event")
            local tap_event = Event:new("Tap"):asUserInput()

            UIManager:userInput(tap_event)

            -- Under non-modal child menu, both child and parent receive the event
            assert.is.same(1, child_calls)
            assert.is.same(1, parent_calls)
        end)
    end)
end)
