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
      dimen = require("ui/geometry"):new({ x = 0, y = 0, w = 100, h = 200 }),
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
    UIManager:scheduleIn(50, "foo")
    assert.are.same(1, #UIManager._task_queue)
    assert.are.same("foo", UIManager._task_queue[1].action)
  end)

  it("should insert new task properly in single task queue", function()
    now = time.monotonic()
    local future_time = now + time.s(10000)
    UIManager:quit()
    UIManager._task_queue = {
      { time = future_time, action = "1", args = {} },
    }

    assert.are.same(1, #UIManager._task_queue)
    UIManager:scheduleIn(150, "quz")
    assert.are.same(2, #UIManager._task_queue)
    assert.are.same("quz", UIManager._task_queue[2].action)

    UIManager:quit()
    UIManager._task_queue = {
      { time = now, action = "1", args = {} },
    }

    assert.are.same(1, #UIManager._task_queue)
    UIManager:scheduleIn(150, "foo")
    assert.are.same(2, #UIManager._task_queue)
    assert.are.same("foo", UIManager._task_queue[1].action)
    UIManager:scheduleIn(155, "bar")
    assert.are.same(3, #UIManager._task_queue)
    assert.are.same("bar", UIManager._task_queue[1].action)
  end)

  it("should insert new task in descendant order", function()
    now = time.monotonic()
    UIManager:quit()
    UIManager._task_queue = {
      { time = now, action = "3", args = {} },
      { time = now - time.us(5), action = "2", args = {} },
      { time = now - time.s(10), action = "1", args = {} },
    }

    -- insert into the tail slot
    UIManager:scheduleIn(10, "foo")
    assert.are.same("foo", UIManager._task_queue[1].action)
    -- insert into the second slot
    UIManager:schedule(now - time.s(5), "bar")
    assert.are.same("bar", UIManager._task_queue[4].action)
    -- insert into the head slot
    UIManager:schedule(now - time.s(15), "baz")
    assert.are.same("baz", UIManager._task_queue[6].action)
    -- insert into the last second slot
    UIManager:scheduleIn(5, "qux")
    assert.are.same("qux", UIManager._task_queue[2].action)
    -- insert into the middle slot
    UIManager:schedule(now - time.us(1), "quux")
    assert.are.same("quux", UIManager._task_queue[4].action)
  end)

  it("should insert new tasks with same times before existing tasks", function()
    now = time.monotonic()
    UIManager:quit()

    -- insert task "5s" between "now" and "10s"
    UIManager:schedule(now, "now")
    assert.are.same("now", UIManager._task_queue[1].action)
    UIManager:schedule(now + time.s(10), "10s")
    assert.are.same("10s", UIManager._task_queue[1].action)
    UIManager:schedule(now + time.s(5), "5s")
    assert.are.same("5s", UIManager._task_queue[2].action)

    -- insert task in place of "10s", as it'll expire shortly after "10s"
    MockTime:increase(0.001)
    UIManager:scheduleIn(10, "foo") -- is a bit later than "10s", as time.monotonic() is used internally
    assert.are.same("foo", UIManager._task_queue[1].action)

    -- insert task in place of "10s", which was just shifted by foo
    UIManager:schedule(now + time.s(10), "bar")
    assert.are.same("bar", UIManager._task_queue[2].action)

    -- insert task in place of "bar"
    UIManager:schedule(now + time.s(10), "baz")
    assert.are.same("baz", UIManager._task_queue[2].action)

    -- insert task in place of "5s"
    UIManager:schedule(now + time.s(5), "nix")
    assert.are.same("nix", UIManager._task_queue[5].action)
    -- "barba" replaces "nix"
    UIManager:scheduleIn(5, "barba") -- is a bit later than "5s", as time.monotonic() is used internally
    assert.are.same("barba", UIManager._task_queue[5].action)

    -- "mama is scheduled now and as such inserted in "now"'s place
    UIManager:schedule(now, "mama")
    assert.are.same("mama", UIManager._task_queue[8].action)

    -- "papa" is shortly after "now", so inserted in its place
    -- NOTE: For the same reason as above, test this last, as time.monotonic may not have moved...
    UIManager:nextTick("papa") -- is a bit later than "now"
    assert.are.same("papa", UIManager._task_queue[8].action)

    -- "letta" is shortly after "papa", so inserted in its place
    UIManager:tickAfterNext("letta")
    assert.are.same("function", type(UIManager._task_queue[8].action))
  end)

  it("should unschedule all the tasks with the same action", function()
    now = time.monotonic()
    UIManager:quit()
    UIManager._task_queue = {
      { time = now, action = "3", args = {} },
      { time = now - time.us(5), action = "2", args = {} },
      { time = now - time.us(6), action = "3", args = {} },
      { time = now - time.s(10), action = "1", args = {} },
      { time = now - time.s(15), action = "3", args = {} },
    }

    -- insert into the tail slot
    UIManager:unschedule("3")
    assert.are.same({
      { time = now - time.us(5), action = "2", args = {} },
      { time = now - time.s(10), action = "1", args = {} },
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
    UIManager:nextTick(function()
      UIManager:nextTick(noop)
    end)
    UIManager:_checkTasks()
    assert.is_true(UIManager._task_queue_dirty)
  end)

  describe("modal widgets", function()
    it("should insert modal widget on top", function()
      -- first modal widget
      UIManager:show(Widget:new({
        x_prefix_test_number = 1,
        modal = true,
      }))
      -- regular widget, should go under modal widget
      UIManager:show(Widget:new({
        x_prefix_test_number = 2,
        modal = nil,
      }))

      assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
      assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
    end)
    it(
      "should insert second modal widget on top of first modal widget",
      function()
        UIManager:show(Widget:new({
          x_prefix_test_number = 3,
          modal = true,
        }))

        assert.equals(2, UIManager._window_stack[1].widget.x_prefix_test_number)
        assert.equals(1, UIManager._window_stack[2].widget.x_prefix_test_number)
        assert.equals(3, UIManager._window_stack[3].widget.x_prefix_test_number)
      end
    )
    it(
      "should place always-on-top widgets above standard widgets, ordered by show time",
      function()
        UIManager._window_stack = {}

        local standard = Widget:new({ id = "standard" })
        local modal = Widget:new({ id = "modal", modal = true })
        local always_on_top = Widget:new({ id = "always_on_top" })
        always_on_top.isAlwaysOnTop = function()
          return true
        end

        UIManager:show(standard)
        UIManager:show(always_on_top)
        UIManager:show(modal)

        assert.is.same(3, #UIManager._window_stack)
        assert.is.same("standard", UIManager._window_stack[1].widget.id)
        assert.is.same("always_on_top", UIManager._window_stack[2].widget.id)
        assert.is.same("modal", UIManager._window_stack[3].widget.id)
      end
    )
  end)

  it("should manage isWindowWidget and onClose triggers on close", function()
    UIManager._window_stack = {}
    local closed = false
    local test_widget = Widget:new({
      onClose = function()
        closed = true
      end,
    })

    UIManager:show(test_widget)
    assert.is_true(UIManager:isWindowWidget(test_widget))

    UIManager:close(test_widget)
    assert.is_false(UIManager:isWindowWidget(test_widget))
    assert.is_true(closed)
  end)

  it("should check active widgets in order", function()
    local call_signals = { false, false, false }
    UIManager._window_stack = {
      {
        widget = {
          handleEvent = function()
            call_signals[1] = true
            return true
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[2] = true
            return true
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[3] = true
            return true
          end,
        },
      },
      { widget = { handleEvent = function() end } },
    }

    UIManager:userInput("foo")
    assert.falsy(call_signals[1])
    assert.falsy(call_signals[2])
    assert.truthy(call_signals[3])
  end)

  it("should handle stack change when checking for active widgets", function()
    -- scenario 1: 2nd widget removes the 3rd widget in the stack
    local call_signals = { 0, 0, 0 }
    UIManager._window_stack = {
      {
        widget = {
          handleEvent = function()
            call_signals[1] = call_signals[1] + 1
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[2] = call_signals[2] + 1
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[3] = call_signals[3] + 1
            table.remove(UIManager._window_stack, 2)
          end,
        },
      },
      { widget = { handleEvent = function() end } },
    }

    UIManager:userInput("foo")
    assert.is.same(call_signals[1], 1)
    assert.is.same(call_signals[2], 0)
    assert.is.same(call_signals[3], 1)

    -- scenario 2: top widget removes itself
    call_signals = { 0, 0, 0 }
    UIManager._window_stack = {
      {
        widget = {
          handleEvent = function()
            call_signals[1] = call_signals[1] + 1
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[2] = call_signals[2] + 1
          end,
        },
      },
      {
        widget = {
          handleEvent = function()
            call_signals[3] = call_signals[3] + 1
            table.remove(UIManager._window_stack, 3)
          end,
        },
      },
    }

    UIManager:userInput("foo")
    assert.is.same(1, call_signals[1])
    assert.is.same(1, call_signals[2])
    assert.is.same(1, call_signals[3])
  end)

  it("should allow events to propagate through toast widgets", function()
    local call_signals = { 0, 0 }
    UIManager._window_stack = {
      {
        widget = {
          handleEvent = function()
            call_signals[1] = call_signals[1] + 1
          end,
        },
      },
      {
        widget = {
          toast = true,
          handleEvent = function()
            call_signals[2] = call_signals[2] + 1
          end,
        },
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
          end,
        }),
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
          end,
        }),
      },
      {
        widget = Widget:new({
          handleEvent = function()
            assert.falsy(true)
          end,
        }),
      },
      {
        widget = Widget:new({
          handleEvent = function()
            assert.falsy(true)
          end,
        }),
      },
      {
        widget = Widget:new({
          handleEvent = function()
            table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
            table.remove(UIManager._window_stack, #UIManager._window_stack - 2)
            table.remove(UIManager._window_stack, #UIManager._window_stack - 1)
          end,
        }),
      },
      {
        widget = Widget:new({
          handleEvent = function()
            assert.truthy(true)
          end,
        }),
      },
    }
    UIManager:broadcastEvent("foo")
    assert.is.same(2, #UIManager._window_stack)

    -- Test inserting a new widget in the stack
    local new_widget = {
      widget = Widget:new({
        handleEvent = function()
          assert.truthy(true)
        end,
      }),
    }
    UIManager._window_stack = {
      {
        widget = Widget:new({
          handleEvent = function()
            table.insert(UIManager._window_stack, new_widget)
          end,
        }),
      },
      {
        widget = Widget:new({
          handleEvent = function()
            assert.truthy(true)
          end,
        }),
      },
    }
    UIManager:broadcastEvent("foo")
    assert.is.same(3, #UIManager._window_stack)
  end)

  it("should handle stack change when closing widgets", function()
    local widget_1 = Widget:new()
    local widget_2 = Widget:new({
      handleEvent = function()
        UIManager:close(widget_1)
      end,
    })
    local widget_3 = Widget:new()
    UIManager._window_stack = {
      { x = 0, y = 0, widget = widget_1 },
      { x = 0, y = 0, widget = widget_2 },
      { x = 0, y = 0, widget = widget_3 },
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
        end,
      })
      local overlay = Widget:new({
        onTap = function()
          overlay_calls = overlay_calls + 1
          return false -- propagate
        end,
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
        end,
      })
      local overlay = Widget:new({
        modal = true,
        onTap = function()
          overlay_calls = overlay_calls + 1
          return false -- propagate
        end,
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
        end,
      })
      local overlay = Widget:new({
        toast = true,
        onTap = function()
          overlay_calls = overlay_calls + 1
          return false -- propagate
        end,
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

    it(
      "should allow parent menu to receive events when child menu is non-modal",
      function()
        local parent_calls = 0
        local child_calls = 0

        local base_view = Widget:new()

        -- TouchMenu (parent)
        local parent_menu = Widget:new({
          onTap = function()
            parent_calls = parent_calls + 1
            return true
          end,
        })

        -- Menu (child dropdown)
        local child_menu = Widget:new({
          onTap = function()
            child_calls = child_calls + 1
            return false -- propagate to parent
          end,
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
      end
    )
  end)

  describe("E2E event propagation and broadcasting scenarios", function()
    before_each(function()
      UIManager._window_stack = {}
    end)

    after_each(function()
      UIManager._window_stack = {}
    end)

    it(
      "should route userInput to top widget and verify sequential walk behavior on master",
      function()
        local base_received = false
        local middle_received = false
        local top_received = false

        local base = Widget:new({
          is_always_active = true, -- but it's base (index 1), so it should be protected/skipped on master
          onTap = function()
            base_received = true
            return true
          end,
        })
        local middle = Widget:new({
          -- not always active, so it should be skipped on master
          onTap = function()
            middle_received = true
            return true
          end,
        })
        local top = Widget:new({
          onTap = function()
            top_received = true
            return false
          end, -- propagates
        })

        UIManager:show(base)
        UIManager:show(middle)
        UIManager:show(top)

        local Event = require("ui/event")
        UIManager:userInput(Event:new("Tap"):asUserInput())

        assert.is_true(top_received)
        assert.is_true(middle_received) -- Middle receives it and consumes it on refactor branch
        assert.is_false(base_received) -- Base is protected and not called since middle consumed it
      end
    )

    it(
      "should broadcast programmatic event to all widgets in the stack top-to-bottom",
      function()
        local order = {}
        local w1 = Widget:new({
          onCustom = function()
            table.insert(order, "bottom")
            return true
          end,
        })
        local w2 = Widget:new({
          onCustom = function()
            table.insert(order, "middle")
            return true
          end,
        })
        local w3 = Widget:new({
          onCustom = function()
            table.insert(order, "top")
            return true
          end,
        })

        UIManager:show(w1)
        UIManager:show(w2)
        UIManager:show(w3)

        UIManager:broadcastEvent("Custom")

        -- Broadcast is sent to all widgets regardless of return value, from top to bottom
        assert.is.same({ "top", "middle", "bottom" }, order)
      end
    )

    it(
      "should handle stack mutation (closing a widget) during broadcastEvent safely",
      function()
        local w1_received = false
        local w2_closed_self = false
        local w3_received = false

        local w1 = Widget:new({
          onCustom = function()
            w1_received = true
            return true
          end,
        })
        local w2 = Widget:new({
          onCustom = function(self)
            w2_closed_self = true
            UIManager:close(self) -- mutate stack
            return true
          end,
        })
        local w3 = Widget:new({
          onCustom = function()
            w3_received = true
            return true
          end,
        })

        UIManager:show(w1)
        UIManager:show(w2)
        UIManager:show(w3)

        assert.has_no.errors(function()
          UIManager:broadcastEvent("Custom")
        end)

        assert.is_true(w3_received)
        assert.is_true(w2_closed_self)
        assert.is_true(w1_received) -- Still receives it safely!
      end
    )
  end)

  describe("askForRestartOrReload", function()
    local old_ReaderUI, old_FileManager
    setup(function()
      old_ReaderUI = package.loaded["apps/reader/readerui"]
      package.loaded["apps/reader/readerui"] = {
        instance = nil,
      }
      old_FileManager = package.loaded["apps/filemanager/filemanager"]
      package.loaded["apps/filemanager/filemanager"] = {
        instance = nil,
      }
    end)

    teardown(function()
      package.loaded["apps/reader/readerui"] = old_ReaderUI
      package.loaded["apps/filemanager/filemanager"] = old_FileManager
    end)

    it(
      "should call askForRestart if ReaderUI.instance and FileManager.instance are nil",
      function()
        local askForRestart_called = false
        local old_askForRestart = UIManager.askForRestart
        UIManager.askForRestart = function(self, _msg)
          askForRestart_called = true
        end

        UIManager:askForRestartOrReload("Test message")
        UIManager:_checkTasks()

        assert.is_true(askForRestart_called)
        UIManager.askForRestart = old_askForRestart
      end
    )

    it("should show reload dialog if ReaderUI.instance is set", function()
      local ReaderUI = package.loaded["apps/reader/readerui"]
      local reload_called = false
      ReaderUI.instance = {
        reloadDocument = function()
          reload_called = true
        end,
      }

      local show_called_with = nil
      local old_show = UIManager.show
      UIManager.show = function(self, widget)
        show_called_with = widget
      end

      UIManager:askForRestartOrReload("Test message")
      UIManager:_checkTasks()

      assert.is_not_nil(show_called_with)
      assert.are.equal("Test message", show_called_with.text)
      assert.are.equal("Later", show_called_with.cancel_text)

      show_called_with:ok_callback()
      assert.is_true(reload_called)

      UIManager.show = old_show
      ReaderUI.instance = nil
    end)

    it(
      "should show reload dialog if FileManager.instance is set and ReaderUI.instance is nil",
      function()
        local FileManager = package.loaded["apps/filemanager/filemanager"]
        local restart_called = false
        FileManager.instance = {
          restart = function()
            restart_called = true
          end,
        }

        local show_called_with = nil
        local old_show = UIManager.show
        UIManager.show = function(self, widget)
          show_called_with = widget
        end

        UIManager:askForRestartOrReload("Test message")
        UIManager:_checkTasks()

        assert.is_not_nil(show_called_with)
        assert.are.equal("Test message", show_called_with.text)
        assert.are.equal("Later", show_called_with.cancel_text)

        show_called_with:ok_callback()
        assert.is_true(restart_called)

        UIManager.show = old_show
        FileManager.instance = nil
      end
    )
  end)
  describe("UIManager Device Power and Control utilities", function()
    it("should handle askForReboot and askForPowerOff dialogs", function()
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      UIManager:askForReboot("Reboot now?")
      UIManager:_checkTasks()
      assert.is_table(shown_widget)
      assert.are_equal("Reboot now?", shown_widget.text)

      shown_widget = nil
      UIManager:askForPowerOff("Power off now?")
      UIManager:_checkTasks()
      assert.is_table(shown_widget)
      assert.are_equal("Power off now?", shown_widget.text)

      UIManager.show = orig_show
    end)

    it("should handle debounce functions", function()
      local count = 0
      local fn = function()
        count = count + 1
      end
      local debounced = UIManager:debounce(0.05, false, fn)

      debounced()
      debounced()
      UIManager:_checkTasks()
    end)

    it("should handle touch ignore state and fast refresh toggles", function()
      UIManager:setIgnoreTouchInput(true)
      UIManager:setIgnoreTouchInput(false)

      UIManager:forceFastRefresh()
      assert.is_true(UIManager:duringForceFastRefresh())
      UIManager:resetForceFastRefresh()
      assert.is_false(UIManager:duringForceFastRefresh())
    end)

    it(
      "should handle input timeouts and closeIfShown / closeIfNotNil",
      function()
        UIManager:setInputTimeout(500)
        UIManager:resetInputTimeout()

        local dummy_widget = { dimen = { x = 0, y = 0, w = 10, h = 10 } }
        UIManager:closeIfShown(dummy_widget)
        UIManager:closeIfNotNil(nil)
        assert.is_nil(UIManager:getTopmostVisibleWidget())
      end
    )

    it("should handle shiftScheduledTasksBy and task time queries", function()
      UIManager:quit()
      local now_time = time.monotonic()
      UIManager:scheduleIn(10, "task10")
      UIManager:scheduleIn(20, "task20")

      local next_time = UIManager:getNextTaskTime()
      assert.is_not_nil(next_time)

      UIManager:shiftScheduledTasksBy(5)
      assert.is_true(UIManager:getNextTaskTime() > next_time)

      -- User action timing
      UIManager:updateLastUserActionTime()
      assert.is_number(UIManager:lastUserActionTime())
      assert.is_number(UIManager:timeSinceLastUserAction())
      assert.is_number(UIManager:getElapsedTimeSinceBoot())
    end)

    it(
      "should handle run forever mode, window stack debug list and topdown iterator",
      function()
        UIManager:setRunForeverMode()
        UIManager:unsetRunForeverMode()

        local w1 = Widget:new({ id = "w1" })
        local w2 = Widget:new({ id = "w2" })
        UIManager:show(w1)
        UIManager:show(w2)

        local list = UIManager:_windowStackDebugList()
        assert.is_string(list)

        local iter_count = 0
        for window in UIManager:topdown_windows_iter() do
          iter_count = iter_count + 1
          assert.is_not_nil(window)
        end
        assert.are.equal(2, iter_count)

        UIManager:close(w1)
        UIManager:close(w2)
      end
    )

    it(
      "should handle ZMQ registration, refresh schedule, and night mode toggle",
      function()
        local dummy_zmq = { id = "zmq1" }
        UIManager:insertZMQ(dummy_zmq)
        UIManager:removeZMQ(dummy_zmq)

        UIManager:scheduleRefresh("fast", nil, false)
        UIManager:ignoreNextRefreshPromote()
        assert.is_boolean(UIManager:fullRefreshPromoteEnabled())

        UIManager:clearRenderStack()
        UIManager:toggleNightMode()
      end
    )

    describe("debounce", function()
      it(
        "executes immediately when immediate = true and allows execution again after timeout",
        function()
          UIManager:quit()
          local call_count = 0
          local last_arg = nil
          local debounced = UIManager:debounce(1.0, true, function(arg)
            call_count = call_count + 1
            last_arg = arg
            return "result_" .. tostring(arg)
          end)

          local res1 = debounced("first")
          assert.are.equal("result_first", res1)
          assert.are.equal(1, call_count)
          assert.are.equal("first", last_arg)

          -- Calling again immediately should not execute action again
          debounced("second")
          assert.are.equal(1, call_count)
          assert.are.equal("first", last_arg)

          -- Advance time past timeout and check tasks to clear is_scheduled
          MockTime:increase(1.1)
          UIManager:_checkTasks()

          -- Next call should execute immediately again
          local res3 = debounced("third")
          assert.are.equal("result_third", res3)
          assert.are.equal(2, call_count)
          assert.are.equal("third", last_arg)
        end
      )

      it(
        "should postpone trailing debounce execution when called again before timeout",
        function()
          UIManager:quit()
          local count = 0
          local debounced = UIManager:debounce(1.0, false, function()
            count = count + 1
          end)

          debounced()
          MockTime:increase(0.6)
          debounced()

          MockTime:increase(0.4) -- now t = 1.0 (only 0.4s after the second call)
          UIManager:_checkTasks()
          -- Intended: since only 0.4s has elapsed since the second call, it should have rescheduled for 0.6s later.
          -- Production bug: time.since(previous_call_at) returns microseconds (e.g. 400000) so seconds (1.0) > passed is false!
          assert.are.equal(0, count)

          MockTime:increase(0.6)
          UIManager:_checkTasks()
          assert.are.equal(1, count)
        end
      )
    end)

    describe("keyEvents", function()
      it(
        "collects sorted active key events across window stack with top window taking precedence",
        function()
          local InputContainer = require("ui/widget/container/inputcontainer")
          local bottom = InputContainer:new({
            key_events = {
              Shared = { { "A" }, doc = "bottom" },
              BottomOnly = { { "B" } },
              Inactive = { { "C" }, is_inactive = true },
              AnyKeyPressed = { { "D" } },
              SelectByShortCut = { { "E" } },
            },
          })
          local top = InputContainer:new({
            key_events = {
              Shared = { { "A" }, doc = "top" },
              TopOnly = { { "T" } },
            },
          })

          UIManager:show(bottom)
          UIManager:show(top)
          finally(function()
            UIManager:close(top)
            UIManager:close(bottom)
          end)

          local collected_keys = {}
          local collected = {}
          for k, v in UIManager:keyEvents() do
            table.insert(collected_keys, k)
            collected[k] = v
          end

          assert.are.same({ "BottomOnly", "Shared", "TopOnly" }, collected_keys)
          assert.is_nil(collected.Inactive)
          assert.is_nil(collected.AnyKeyPressed)
          assert.is_nil(collected.SelectByShortCut)
          assert.are.equal("top", collected.Shared.doc)
        end
      )

      it(
        "should collect keyEvents from child InputContainers inside layout containers without key_events",
        function()
          local InputContainer = require("ui/widget/container/inputcontainer")
          local FrameContainer = require("ui/widget/container/framecontainer")
          local child = InputContainer:new({
            dimen = require("ui/geometry"):new({
              x = 0,
              y = 0,
              w = 100,
              h = 100,
            }),
            key_events = {
              ChildAction = { { "Enter" }, doc = "child" },
            },
          })
          local frame = FrameContainer:new({
            padding = 0,
            margin = 0,
            bordersize = 0,
            child,
          })
          -- FrameContainer.key_events is nil
          UIManager:show(frame)
          finally(function()
            UIManager:close(frame)
          end)

          local collected = {}
          for k, v in UIManager:keyEvents() do
            collected[k] = v
          end
          -- Production bug: uimanager.lua:1835-1837 returns early when w.key_events is nil,
          -- failing to recurse into child widgets inside containers without key_events.
          assert.is_not_nil(collected.ChildAction)
        end
      )
    end)

    describe(
      "handleInputEvent out-of-order filtering and event handlers",
      function()
        it(
          "dispatches to custom event_handlers and bypasses userInput",
          function()
            local orig_userInput = UIManager.userInput
            local user_input_called = false
            UIManager.userInput = function()
              user_input_called = true
            end
            local custom_handler_called = false
            UIManager.event_handlers["CustomRaw"] = function()
              custom_handler_called = true
            end
            finally(function()
              UIManager.userInput = orig_userInput
              UIManager.event_handlers["CustomRaw"] = nil
            end)

            UIManager:handleInputEvent("CustomRaw")
            assert.is_true(custom_handler_called)
            assert.is_false(user_input_called)
          end
        )

        it(
          "filters out-of-order tap/swipe and key press events while allowing hold/pan",
          function()
            local orig_userInput = UIManager.userInput
            local orig_last_repaint = UIManager._last_repaint_time
            local orig_setting =
              G_reader_settings:read("disable_out_of_order_input")
            local called_events = {}
            UIManager.userInput = function(_, ev)
              table.insert(called_events, ev)
            end
            finally(function()
              UIManager.userInput = orig_userInput
              UIManager._last_repaint_time = orig_last_repaint
              G_reader_settings:save("disable_out_of_order_input", orig_setting)
            end)

            G_reader_settings:save("disable_out_of_order_input", true)
            UIManager._last_repaint_time = 200

            -- 1. Stale tap gesture (time 100 < 200) -> ignored
            called_events = {}
            UIManager:handleInputEvent({
              handler = "onGesture",
              args = { { ges = "tap", time = 100 } },
            })
            assert.are.equal(0, #called_events)

            -- 2. Stale swipe gesture (time 100 < 200) -> ignored
            UIManager:handleInputEvent({
              handler = "onGesture",
              args = { { ges = "swipe", time = 100 } },
            })
            assert.are.equal(0, #called_events)

            -- 3. Stale hold gesture (time 100 < 200) -> NOT ignored
            UIManager:handleInputEvent({
              handler = "onGesture",
              args = { { ges = "hold", time = 100 } },
            })
            assert.are.equal(1, #called_events)

            -- 4. Stale pan gesture (time 100 < 200) -> NOT ignored
            called_events = {}
            UIManager:handleInputEvent({
              handler = "onGesture",
              args = { { ges = "pan", time = 100 } },
            })
            assert.are.equal(1, #called_events)

            -- 5. Stale key press (time 100 < 200) -> ignored
            called_events = {}
            UIManager:handleInputEvent({
              handler = "onKeyPress",
              time = 100,
            })
            assert.are.equal(0, #called_events)

            -- 6. Fresh key press (time 250 > 200) -> called
            UIManager:handleInputEvent({
              handler = "onKeyPress",
              time = 250,
            })
            assert.are.equal(1, #called_events)

            -- 7. Stale tap with disable_out_of_order_input false -> called
            called_events = {}
            G_reader_settings:save("disable_out_of_order_input", false)
            UIManager:handleInputEvent({
              handler = "onGesture",
              args = { { ges = "tap", time = 100 } },
            })
            assert.are.equal(1, #called_events)
          end
        )
      end
    )

    describe(
      "_decideRefreshMode, cropping_region, and forceRepaintIfFastRefreshEnabled",
      function()
        it(
          "decides refresh mode based on a2, duringForceFastRefresh, full promotion, and avoid_flashing_ui",
          function()
            local Geom = require("ui/geometry")
            local Screen = require("device").screen
            local orig_force = UIManager.duringForceFastRefresh
            local orig_low_pan = G_named_settings.low_pan_rate
            local orig_full_count = UIManager._full_refresh_count
            local orig_refresh_count = UIManager._refresh_count
            local orig_avoid = G_reader_settings:read("avoid_flashing_ui")
            finally(function()
              UIManager.duringForceFastRefresh = orig_force
              G_named_settings.low_pan_rate = orig_low_pan
              UIManager._full_refresh_count = orig_full_count
              UIManager._refresh_count = orig_refresh_count
              G_reader_settings:save("avoid_flashing_ui", orig_avoid)
            end)

            local full_rect = Geom:new({
              x = 0,
              y = 0,
              w = Screen:getWidth(),
              h = Screen:getHeight(),
            })
            local half_rect = Geom:new({
              x = 0,
              y = 0,
              w = Screen:getWidth(),
              h = math.floor(Screen:getHeight() * 0.6),
            })
            local small_rect = Geom:new({ x = 0, y = 0, w = 10, h = 10 })

            -- 1. "a2" returns "fast"
            assert.are.equal(
              "fast",
              UIManager:_decideRefreshMode({ mode = "a2", region = small_rect })
            )

            -- 2. duringForceFastRefresh and low_pan_rate downgrades full to fast
            UIManager.duringForceFastRefresh = function()
              return true
            end
            G_named_settings.low_pan_rate = function()
              return true
            end
            assert.are.equal(
              "fast",
              UIManager:_decideRefreshMode({
                mode = "full",
                region = small_rect,
              })
            )

            UIManager.duringForceFastRefresh = function()
              return false
            end
            G_named_settings.low_pan_rate = function()
              return false
            end

            -- 3. Full refresh promotion
            UIManager._full_refresh_count = 3
            UIManager._refresh_count = 3
            -- Area >= 80% promotes to full
            assert.are.equal(
              "full",
              UIManager:_decideRefreshMode({ mode = "ui", region = full_rect })
            )
            -- Area between 50% and 80% promotes to flashui
            assert.are.equal(
              "flashui",
              UIManager:_decideRefreshMode({ mode = "ui", region = half_rect })
            )

            -- 4. avoid_flashing_ui downgrades
            UIManager._refresh_count = 0
            G_reader_settings:save("avoid_flashing_ui", true)
            assert.are.equal(
              "ui",
              UIManager:_decideRefreshMode({
                mode = "flashui",
                region = small_rect,
              })
            )
            assert.are.equal(
              "partial",
              UIManager:_decideRefreshMode({
                mode = "flashpartial",
                region = small_rect,
              })
            )
            assert.are.equal(
              "ui",
              UIManager:_decideRefreshMode({
                mode = "partial",
                region = small_rect,
              })
            )
            assert.are.equal(
              "partial",
              UIManager:_decideRefreshMode({
                mode = "full",
                region = small_rect,
              })
            )

            -- When avoid_flashing_ui is false, fast promotes to ui
            G_reader_settings:save("avoid_flashing_ui", false)
            assert.are.equal(
              "ui",
              UIManager:_decideRefreshMode({
                mode = "fast",
                region = small_rect,
              })
            )
          end
        )

        it(
          "calculates cropping_region and intersects with parent cropping_widget",
          function()
            local Geom = require("ui/geometry")
            -- Nil width or height returns nil
            local bad_widget = Widget:new({
              dimen = Geom:new({ x = 0, y = 0, w = 0, h = 0 }),
            })
            bad_widget.getSize = function()
              return { x = 0, y = 0, w = nil, h = nil }
            end
            assert.is_nil(UIManager:cropping_region(bad_widget))

            -- Intersects with parent.cropping_widget
            local crop_box = Geom:new({ x = 10, y = 10, w = 50, h = 50 })
            local child_widget = Widget:new({
              dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
            })
            local crop_container = Widget:new({
              child_widget,
              getCropRegion = function()
                return crop_box
              end,
            })
            local parent_window_widget = Widget:new({
              crop_container,
              dimen = Geom:new({ x = 0, y = 0, w = 200, h = 200 }),
              cropping_widget = crop_container,
            })

            UIManager:show(parent_window_widget)
            finally(function()
              UIManager:close(parent_window_widget)
            end)

            local region = UIManager:cropping_region(child_widget)
            assert.is_not_nil(region)
            assert.are.equal(10, region.x)
            assert.are.equal(10, region.y)
            assert.are.equal(50, region.w)
            assert.are.equal(50, region.h)
          end
        )

        it(
          "triggers forceRepaint when fast_screen_refresh is enabled",
          function()
            local orig_fast = G_named_settings.fast_screen_refresh
            local orig_force = UIManager.forceRepaint
            local force_called = 0
            UIManager.forceRepaint = function()
              force_called = force_called + 1
            end
            finally(function()
              G_named_settings.fast_screen_refresh = orig_fast
              UIManager.forceRepaint = orig_force
            end)

            G_named_settings.fast_screen_refresh = function()
              return false
            end
            UIManager:forceRepaintIfFastRefreshEnabled()
            assert.are.equal(0, force_called)

            G_named_settings.fast_screen_refresh = function()
              return true
            end
            UIManager:forceRepaintIfFastRefreshEnabled()
            assert.are.equal(1, force_called)
          end
        )
      end
    )
  end)
end)
