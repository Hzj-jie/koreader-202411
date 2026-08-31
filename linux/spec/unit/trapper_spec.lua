describe("Trapper module", function()
  local Trapper
  local UIManager
  local Widget
  local logger

  setup(function()
    require("commonrequire")
    Trapper = require("ui/trapper")
    UIManager = require("ui/uimanager")
    Widget = require("ui/widget/widget")
    logger = require("logger")
  end)

  before_each(function()
    Trapper:reset()
  end)

  it("should initialize Trapper module", function()
    assert.is_table(Trapper)
    assert.is_function(Trapper.wrap)
    assert.is_function(Trapper.isWrapped)
    assert.is_function(Trapper.clear)
    assert.is_function(Trapper.reset)
    assert.is_function(Trapper.setPausedText)
    assert.is_function(Trapper.info)
    assert.is_function(Trapper.confirm)
    assert.is_function(Trapper.dismissablePopen)
    assert.is_function(Trapper.dismissableRunInSubprocess)
  end)

  describe("wrapping and state management", function()
    it(
      "should execute wrapped functions successfully and manage standby state",
      function()
        local prevent_spy = spy.on(UIManager, "preventStandby")
        local allow_spy = spy.on(UIManager, "allowStandby")
        local executed = false

        local ok, result = Trapper:wrap(function()
          executed = true
          assert.is_true(Trapper:isWrapped())
        end)

        assert.is_true(ok)
        assert.is_true(result)
        assert.is_true(executed)
        assert.spy(prevent_spy).was.called(1)
        assert.spy(allow_spy).was.called(1)

        prevent_spy:revert()
        allow_spy:revert()
      end
    )

    it(
      "should catch and log errors in wrapped functions while resetting standby",
      function()
        local prevent_spy = spy.on(UIManager, "preventStandby")
        local allow_spy = spy.on(UIManager, "allowStandby")
        local err_called = false
        local orig_err = logger.err
        logger.err = function(...)
          err_called = true
          orig_err(...)
        end

        local ok, result = Trapper:wrap(function()
          error("test wrapped error")
        end)

        assert.is_true(ok)
        assert.is_false(result)
        assert.spy(prevent_spy).was.called(1)
        assert.spy(allow_spy).was.called(1)
        assert.is_true(err_called)

        prevent_spy:revert()
        allow_spy:revert()
        logger.err = orig_err
      end
    )

    it(
      "should report isWrapped correctly depending on execution context",
      function()
        assert.is_false(Trapper:isWrapped())
        Trapper:wrap(function()
          assert.is_true(Trapper:isWrapped())
        end)
        assert.is_false(Trapper:isWrapped())
      end
    )

    it("should set and reset paused text", function()
      -- Unwrapped setPausedText does nothing
      Trapper:setPausedText("Custom Paused", "Custom Abort", "Custom Continue")
      assert.is_nil(Trapper.paused_text)

      -- Wrapped setPausedText sets fields
      Trapper:wrap(function()
        Trapper:setPausedText(
          "Custom Paused",
          "Custom Abort",
          "Custom Continue"
        )
      end)

      assert.is_same("Custom Paused", Trapper.paused_text)
      assert.is_same("Custom Abort", Trapper.paused_abort_text)
      assert.is_same("Custom Continue", Trapper.paused_continue_text)

      Trapper:reset()
      assert.is_nil(Trapper.paused_text)
      assert.is_nil(Trapper.paused_abort_text)
      assert.is_nil(Trapper.paused_continue_text)
    end)

    it("should clear current widget on clear and reset when wrapped", function()
      local close_spy = spy.on(UIManager, "close")
      local repaint_spy = spy.on(UIManager, "forceRepaint")

      local dummy_widget = Widget:new({})
      Trapper.current_widget = dummy_widget

      -- Unwrapped clear does nothing
      Trapper:clear()
      assert.is_same(dummy_widget, Trapper.current_widget)

      -- Wrapped clear closes widget and repaints
      Trapper:wrap(function()
        Trapper:clear()
      end)

      assert.is_nil(Trapper.current_widget)
      assert.spy(close_spy).was.called()
      assert.spy(repaint_spy).was.called()

      close_spy:revert()
      repaint_spy:revert()
    end)
  end)

  describe("info method", function()
    it("should log and return true when called unwrapped", function()
      local info_spy = spy.on(logger, "info")
      local ret = Trapper:info("Unwrapped info message")
      assert.is_true(ret)
      assert.spy(info_spy).was.called()
      info_spy:revert()
    end)

    it("should create and show InfoMessage when called wrapped", function()
      local show_spy = spy.on(UIManager, "show")
      local repaint_spy = spy.on(UIManager, "forceRepaint")

      Trapper:wrap(function()
        local res = Trapper:info("First message")
        assert.is_true(res)
        assert.is_not_nil(Trapper.current_widget)
        assert.is_true(Trapper.current_widget.is_infomessage)
        assert.is_same("First message", Trapper.current_widget.text)
      end)

      assert.spy(show_spy).was.called()
      assert.spy(repaint_spy).was.called()

      show_spy:revert()
      repaint_spy:revert()
    end)

    it(
      "should replace existing InfoMessage after timeout when not dismissed",
      function()
        local orig_scheduleIn = UIManager.scheduleIn

        Trapper:wrap(function()
          Trapper:info("Message 1")
          local widget1 = Trapper.current_widget

          -- Second call to info: should schedule go_on_func
          -- We trigger scheduled go_on_func manually
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end

          local res = Trapper:info("Message 2")
          assert.is_true(res)
          assert.is_not_nil(Trapper.current_widget)
          assert.is_not_same(widget1, Trapper.current_widget)
          assert.is_same("Message 2", Trapper.current_widget.text)
        end)

        UIManager.scheduleIn = orig_scheduleIn
      end
    )

    it("should handle dismissal and resume on continue", function()
      local orig_scheduleIn = UIManager.scheduleIn
      local orig_show = UIManager.show

      Trapper:wrap(function()
        Trapper:info("Message 1")
        local prev_widget = Trapper.current_widget

        -- Intercept scheduleIn to trigger dismiss_callback instead of timeout
        UIManager.scheduleIn = function(_, delay, callback)
          prev_widget.dismiss_callback()
        end

        -- Intercept UIManager.show when ConfirmBox (abort_box) is shown to click 'Continue'
        UIManager.show = function(_, widget)
          if widget.cancel_callback then
            widget.cancel_callback()
          end
        end

        local res = Trapper:info("Message 2")
        assert.is_true(res)
      end)

      UIManager.scheduleIn = orig_scheduleIn
      UIManager.show = orig_show
    end)

    it("should handle dismissal and abort on ok_callback", function()
      local orig_scheduleIn = UIManager.scheduleIn
      local orig_show = UIManager.show

      Trapper:wrap(function()
        Trapper:info("Message 1")
        local prev_widget = Trapper.current_widget

        UIManager.scheduleIn = function(_, delay, callback)
          prev_widget.dismiss_callback()
        end

        UIManager.show = function(_, widget)
          if widget.ok_callback then
            widget.ok_callback()
          end
        end

        local res = Trapper:info("Message 2")
        assert.is_false(res)
      end)

      UIManager.scheduleIn = orig_scheduleIn
      UIManager.show = orig_show
    end)

    it("should perform fast refresh when fast_refresh is true", function()
      local Screen = require("device").screen
      local refresh_spy = spy.on(Screen, "refreshUI")

      Trapper:wrap(function()
        Trapper:info("Initial text")
        local orig_widget = Trapper.current_widget
        orig_widget.movable = {
          getMovedOffset = function()
            return { x = 0, y = 0 }
          end,
          setMovedOffset = function() end,
        }
        orig_widget.paintTo = function() end
        orig_widget[1] = { { dimen = { x = 0, y = 0, w = 10, h = 10 } } }

        local res = Trapper:info("Refreshed text", true)
        assert.is_true(res)
        assert.is_same("Refreshed text", Trapper.current_widget.text)
        assert.is_same(orig_widget, Trapper.current_widget)
      end)

      refresh_spy:revert()
    end)
  end)

  describe("confirm method", function()
    it("should return true when called unwrapped", function()
      local info_spy = spy.on(logger, "info")
      local res = Trapper:confirm("Are you sure?")
      assert.is_true(res)
      assert.spy(info_spy).was.called()
      info_spy:revert()
    end)

    it("should show ConfirmBox and return true when OK is tapped", function()
      local orig_show = UIManager.show

      Trapper:wrap(function()
        UIManager.show = function(_, widget)
          if widget.ok_callback then
            widget.ok_callback()
          end
        end

        local res = Trapper:confirm("Proceed?", "No", "Yes")
        assert.is_true(res)
      end)

      UIManager.show = orig_show
    end)

    it(
      "should show ConfirmBox and return false when Cancel is tapped",
      function()
        local orig_show = UIManager.show

        Trapper:wrap(function()
          UIManager.show = function(_, widget)
            if widget.cancel_callback then
              widget.cancel_callback()
            end
          end

          local res = Trapper:confirm("Proceed?", "No", "Yes")
          assert.is_false(res)
        end)

        UIManager.show = orig_show
      end
    )

    it(
      "should close pre-existing widget before displaying ConfirmBox",
      function()
        local close_spy = spy.on(UIManager, "close")
        local orig_show = UIManager.show

        Trapper:wrap(function()
          Trapper:info("Existing info message")
          local info_widget = Trapper.current_widget

          UIManager.show = function(_, widget)
            if widget.ok_callback then
              widget.ok_callback()
            end
          end

          Trapper:confirm("Question?")
          assert.spy(close_spy).was.called_with(UIManager, info_widget)
        end)

        close_spy:revert()
        UIManager.show = orig_show
      end
    )
  end)

  describe("dismissablePopen method", function()
    it("should execute blocking io.popen when unwrapped", function()
      local warn_spy = spy.on(logger, "warn")
      local ok, output = Trapper:dismissablePopen("echo 'hello trapper'")
      assert.is_true(ok)
      assert.is_string(output)
      assert.is_not_nil(output:find("hello trapper"))
      assert.spy(warn_spy).was.called()
      warn_spy:revert()
    end)

    it(
      "should execute dismissablePopen inside coroutine with string widget",
      function()
        local show_spy = spy.on(UIManager, "show")
        local close_spy = spy.on(UIManager, "close")
        local orig_scheduleIn = UIManager.scheduleIn

        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end

          local ok, output =
            Trapper:dismissablePopen("echo 'coroutine popen'", "Running...")
          assert.is_true(ok)
          assert.is_string(output)
          assert.is_not_nil(output:find("coroutine popen"))
        end)

        show_spy:revert()
        close_spy:revert()
        UIManager.scheduleIn = orig_scheduleIn
      end
    )

    it("should handle dismissal in dismissablePopen", function()
      local orig_scheduleIn = UIManager.scheduleIn

      Trapper:wrap(function()
        local test_widget
        local orig_show = UIManager.show
        UIManager.show = function(_, widget)
          test_widget = widget
        end

        UIManager.scheduleIn = function(_, delay, callback)
          if test_widget and test_widget.dismiss_callback then
            test_widget.dismiss_callback()
          end
        end

        local ok, output =
          Trapper:dismissablePopen("sleep 5; echo 'done'", "Dismiss me")
        assert.is_false(ok)
        assert.is_nil(output)
        UIManager.show = orig_show
      end)

      UIManager.scheduleIn = orig_scheduleIn
    end)

    it(
      "should support table, boolean and nil trap_widget options in dismissablePopen",
      function()
        local orig_scheduleIn = UIManager.scheduleIn

        -- Test with table widget
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local custom_widget = { dismiss_callback = nil }
          local ok, output =
            Trapper:dismissablePopen("echo 'table widget'", custom_widget)
          assert.is_true(ok)
          assert.is_not_nil(output:find("table widget"))
        end)

        -- Test with nil (resend_event = true)
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local ok, output = Trapper:dismissablePopen("echo 'nil widget'", nil)
          assert.is_true(ok)
          assert.is_not_nil(output:find("nil widget"))
        end)

        -- Test with false (resend_event = false)
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local ok, output =
            Trapper:dismissablePopen("echo 'false widget'", false)
          assert.is_true(ok)
          assert.is_not_nil(output:find("false widget"))
        end)

        UIManager.scheduleIn = orig_scheduleIn
      end
    )
  end)

  describe("dismissableRunInSubprocess method", function()
    it("should execute task in-process when unwrapped", function()
      local warn_spy = spy.on(logger, "warn")
      local run_count = 0
      local ok, res = Trapper:dismissableRunInSubprocess(function()
        run_count = run_count + 1
        return "done"
      end, "Processing...")

      assert.is_true(ok)
      assert.is_same(1, run_count)
      assert.is_same("done", res)
      assert.spy(warn_spy).was.called()
      warn_spy:revert()
    end)

    it(
      "should execute task in subprocess returning simple string when wrapped",
      function()
        local orig_scheduleIn = UIManager.scheduleIn

        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end

          local ok, res = Trapper:dismissableRunInSubprocess(function()
            return "subprocess result string"
          end, "Working...", true)

          assert.is_true(ok)
          assert.is_same("subprocess result string", res)
        end)

        UIManager.scheduleIn = orig_scheduleIn
      end
    )

    it(
      "should execute task in subprocess returning complex table when wrapped",
      function()
        local orig_scheduleIn = UIManager.scheduleIn

        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end

          local ok, a, b = Trapper:dismissableRunInSubprocess(function()
            return { key = "val" }, 123
          end, "Working...", false)

          assert.is_true(ok)
          assert.is_table(a)
          assert.is_same("val", a.key)
          assert.is_same(123, b)
        end)

        UIManager.scheduleIn = orig_scheduleIn
      end
    )

    it(
      "should handle widget parameters (table, string, nil, false) in dismissableRunInSubprocess",
      function()
        local orig_scheduleIn = UIManager.scheduleIn

        -- String widget
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local ok, res = Trapper:dismissableRunInSubprocess(function()
            return "s"
          end, "Text Widget", true)
          assert.is_true(ok)
          assert.is_same("s", res)
        end)

        -- Table widget
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local custom_widget = {}
          local ok, res = Trapper:dismissableRunInSubprocess(function()
            return "t"
          end, custom_widget, true)
          assert.is_true(ok)
          assert.is_same("t", res)
        end)

        -- nil widget
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local ok, res = Trapper:dismissableRunInSubprocess(function()
            return "n"
          end, nil, true)
          assert.is_true(ok)
          assert.is_same("n", res)
        end)

        -- false widget
        Trapper:wrap(function()
          UIManager.scheduleIn = function(_, delay, callback)
            callback()
          end
          local ok, res = Trapper:dismissableRunInSubprocess(function()
            return "f"
          end, false, true)
          assert.is_true(ok)
          assert.is_same("f", res)
        end)

        UIManager.scheduleIn = orig_scheduleIn
      end
    )

    it("should handle dismissal in dismissableRunInSubprocess", function()
      local ffiutil = require("ffi/util")
      local orig_term = ffiutil.terminateSubProcess
      local orig_scheduleIn = UIManager.scheduleIn
      local orig_show = UIManager.show

      Trapper:wrap(function()
        local test_widget
        UIManager.show = function(_, widget)
          test_widget = widget
        end

        UIManager.scheduleIn = function(_, delay, callback)
          if test_widget and test_widget.dismiss_callback then
            test_widget.dismiss_callback()
          end
        end

        local term_called = false
        ffiutil.terminateSubProcess = function(pid)
          term_called = true
        end

        local ok, res = Trapper:dismissableRunInSubprocess(function()
          local start = os.time()
          while os.time() - start < 2 do
          end
          return "never reached"
        end, "Cancel me", true)

        assert.is_false(ok)
        assert.is_nil(res)
        assert.is_true(term_called)
      end)

      ffiutil.terminateSubProcess = orig_term
      UIManager.scheduleIn = orig_scheduleIn
      UIManager.show = orig_show
    end)
  end)
end)

describe("Trapper confirmation, pause, and popen edge cases", function()
  local Trapper = require("ui/trapper")
  local UIManager = require("ui/uimanager")
  local ffiutil = require("ffi/util")
  local buffer = require("string.buffer")

  it("should handle setPausedText and confirm dialog", function()
    local shown_confirm
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_confirm = w
    end

    Trapper:wrap(function()
      Trapper:setPausedText("Pause Title", "Abort Now", "Keep Going")
      assert.are_equal("Pause Title", Trapper.paused_text)
      assert.are_equal("Abort Now", Trapper.paused_abort_text)
      assert.are_equal("Keep Going", Trapper.paused_continue_text)

      UIManager.scheduleIn = function(_, _, cb)
        if shown_confirm and shown_confirm.ok_callback then
          shown_confirm.ok_callback()
        end
      end
      local ans = Trapper:confirm("Are you sure?", "Yes", "No")
      assert.is_true(ans)
    end)

    UIManager.show = orig_show
  end)

  it("should handle info widget text update", function()
    Trapper:wrap(function()
      local ok = Trapper:info("Initial Text")
      assert.is_true(ok)
      assert.is_not_nil(Trapper.current_widget)
      Trapper:info("Updated Text", true)
    end)
    Trapper:clear()
  end)

  it("should handle collect_and_clean callbacks for dismissed popen", function()
    local orig_scheduleIn = UIManager.scheduleIn
    local scheduled_callbacks = {}
    UIManager.scheduleIn = function(_, delay, cb)
      table.insert(scheduled_callbacks, cb)
    end

    Trapper:wrap(function()
      local custom_widget = { dismiss_callback = nil }
      -- Trigger dismiss immediately
      UIManager.scheduleIn = function(_, delay, cb)
        custom_widget.dismiss_callback()
      end

      local ok, out = Trapper:dismissablePopen("echo 'dismissed'", custom_widget)
      assert.is_false(ok)
      assert.is_nil(out)
    end)

    UIManager.scheduleIn = orig_scheduleIn
  end)

  it("should handle dismissableRunInSubprocess with various return types and warnings", function()
    local orig_scheduleIn = UIManager.scheduleIn
    local orig_runInSubProcess = ffiutil.runInSubProcess
    local orig_readAllFromFD = ffiutil.readAllFromFD
    local orig_isSubProcessDone = ffiutil.isSubProcessDone
    local orig_getNonBlockingReadSize = ffiutil.getNonBlockingReadSize

    -- 1. Task returning non-string when task_returns_simple_string is true
    Trapper:wrap(function()
      UIManager.scheduleIn = function(_, delay, cb) cb() end
      local ok, res = Trapper:dismissableRunInSubprocess(function()
        return 12345 -- not a string
      end, "Checking...", true)
      assert.is_true(ok)
    end)

    -- 2. Task returning non-serializable object (e.g. function)
    Trapper:wrap(function()
      UIManager.scheduleIn = function(_, delay, cb) cb() end
      local ok, res = Trapper:dismissableRunInSubprocess(function()
        return function() end -- not serializable
      end, "Checking...", false)
      assert.is_true(ok)
    end)

    -- 3. Subprocess done without output
    Trapper:wrap(function()
      UIManager.scheduleIn = function(_, delay, cb) cb() end
      ffiutil.isSubProcessDone = function() return true end
      ffiutil.getNonBlockingReadSize = function() return 0 end
      ffiutil.readAllFromFD = function() return "" end

      local ok, res = Trapper:dismissableRunInSubprocess(function() end, false, true)
      assert.is_true(ok)
      assert.is_nil(res)
    end)

    -- 4. Malformed serialized data handling
    Trapper:wrap(function()
      UIManager.scheduleIn = function(_, delay, cb) cb() end
      ffiutil.isSubProcessDone = function() return true end
      ffiutil.getNonBlockingReadSize = function() return 10 end
      ffiutil.readAllFromFD = function() return "not_valid_msgpack_binary" end

      local ok, res = Trapper:dismissableRunInSubprocess(function() end, false, false)
      assert.is_true(ok)
      assert.is_nil(res)
    end)

    -- 5. Subprocess output read while process still alive (scheduled cleanup)
    Trapper:wrap(function()
      local done_state = false
      local cleanup_cb
      UIManager.scheduleIn = function(_, delay, cb)
        cleanup_cb = cb
        cb()
      end
      ffiutil.isSubProcessDone = function()
        return done_state
      end
      ffiutil.getNonBlockingReadSize = function() return 5 end
      ffiutil.readAllFromFD = function() return buffer.encode({ "hello" }) end

      local ok, res = Trapper:dismissableRunInSubprocess(function() return "hello" end, false, false)
      assert.is_true(ok)
      assert.are_equal("hello", res)

      -- Trigger cleanup callback while still alive, then when done
      if cleanup_cb then
        cleanup_cb()
        done_state = true
        cleanup_cb()
      end
    end)

    -- 6. Dismissed subprocess collect_and_clean callback
    Trapper:wrap(function()
      local custom_widget = {}
      local cleanup_cb
      UIManager.scheduleIn = function(_, delay, cb)
        cleanup_cb = cb
      end

      -- Trigger dismissal
      local old_term = ffiutil.terminateSubProcess
      ffiutil.terminateSubProcess = function() end

      -- Yield and trigger dismiss_callback
      local co = coroutine.running()
      UIManager.scheduleIn = function(_, delay, cb)
        custom_widget.dismiss_callback()
      end

      local ok, res = Trapper:dismissableRunInSubprocess(function() return "x" end, custom_widget, true)
      assert.is_false(ok)

      -- Run collect_and_clean branches
      ffiutil.isSubProcessDone = function() return false end
      ffiutil.getNonBlockingReadSize = function() return 1 end
      if cleanup_cb then
        cleanup_cb()
      end
      ffiutil.isSubProcessDone = function() return true end
      if cleanup_cb then
        cleanup_cb()
      end

      ffiutil.terminateSubProcess = old_term
    end)

    ffiutil.isSubProcessDone = orig_isSubProcessDone
    ffiutil.getNonBlockingReadSize = orig_getNonBlockingReadSize
    ffiutil.readAllFromFD = orig_readAllFromFD
    ffiutil.runInSubProcess = orig_runInSubProcess
    UIManager.scheduleIn = orig_scheduleIn
  end)
end)
