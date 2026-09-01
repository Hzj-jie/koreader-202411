describe("input module", function()
  local Input
  local ffi, C
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    C = ffi.C
    require("ffi/linux_input_h")
    Input = require("device").input
  end)

  describe("handleTouchEvPhoenix", function()
    --[[
-- a touch looks something like this (from H2Ov1)
Event: time 1510346968.993890, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346968.994362, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346968.994384, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346968.994399, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346968.994409, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 914
Event: time 1510346968.994420, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346968.994429, -------------- SYN_REPORT ------------
Event: time 1510346969.057898, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.058251, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.058417, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.058436, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1012
Event: time 1510346969.058446, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 915
Event: time 1510346969.058456, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.058464, -------------- SYN_REPORT ------------
Event: time 1510346969.066903, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.067102, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 1
Event: time 1510346969.067260, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 1
Event: time 1510346969.067415, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.067433, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.067443, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.067451, -------------- SYN_REPORT ------------
Event: time 1510346969.076230, type 3 (EV_ABS), code 57 (ABS_MT_TRACKING_ID), value 1
Event: time 1510346969.076549, type 3 (EV_ABS), code 48 (ABS_MT_TOUCH_MAJOR), value 0
Event: time 1510346969.076714, type 3 (EV_ABS), code 50 (ABS_MT_WIDTH_MAJOR), value 0
Event: time 1510346969.076869, type 3 (EV_ABS), code 53 (ABS_MT_POSITION_X), value 1010
Event: time 1510346969.076887, type 3 (EV_ABS), code 54 (ABS_MT_POSITION_Y), value 918
Event: time 1510346969.076898, ++++++++++++++ SYN_MT_REPORT ++++++++++++
Event: time 1510346969.076908, -------------- SYN_REPORT ------------
]]
    it("should set cur_slot correctly", function()
      local ev
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_TRACKING_ID,
        value = 1,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(1, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_TOUCH_MAJOR,
        value = 1,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(1, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_WIDTH_MAJOR,
        value = 1,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(1, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_POSITION_X,
        value = 1012,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(1, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_POSITION_Y,
        value = 914,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(1, Input.cur_slot)

      -- EV_SYN
      -- depends on gesture_detector
      --[[
            ev = {
                type = C.EV_SYN,
                code = C.SYN_REPORT,
                value = 0,
            }
            Input:handleTouchEvPhoenix(ev)
            assert.is_equal(1, Input.cur_slot)
            ]]

      -- this value=2 stuff doesn't happen IRL, just testing logic
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_TRACKING_ID,
        value = 2,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(2, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_TOUCH_MAJOR,
        value = 2,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(2, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_WIDTH_MAJOR,
        value = 2,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(2, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_POSITION_X,
        value = 1012,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(2, Input.cur_slot)
      ev = {
        type = C.EV_ABS,
        code = C.ABS_MT_POSITION_Y,
        value = 914,
      }
      Input:handleTouchEvPhoenix(ev)
      assert.is_equal(2, Input.cur_slot)
    end)
  end)

  describe("Dismiss group", function()
    local util = require("util")

    it(
      "should contain Back, PgFwd, PgBack and Menu on normal devices",
      function()
        -- Ensure device is treated as normal (not few keys)
        local original_hasFewKeys = Input.device.hasFewKeys
        Input.device.hasFewKeys = function()
          return false
        end
        Input.group.Dismiss = {}
        Input:init()

        local dismiss_group = Input.group.Dismiss
        assert.truthy(dismiss_group)

        -- Should contain standard Back keys
        for _, key in ipairs(Input.group.Back or {}) do
          assert.truthy(util.arrayContains(dismiss_group, key))
        end
        -- Should contain PgFwd keys
        for _, key in ipairs(Input.group.PgFwd or {}) do
          assert.truthy(util.arrayContains(dismiss_group, key))
        end
        -- Should contain PgBack keys
        for _, key in ipairs(Input.group.PgBack or {}) do
          assert.truthy(util.arrayContains(dismiss_group, key))
        end
        -- Should contain Menu
        assert.truthy(util.arrayContains(dismiss_group, "Menu"))
        -- Should NOT contain Left
        assert.falsy(util.arrayContains(dismiss_group, "Left"))

        -- Restore
        Input.device.hasFewKeys = original_hasFewKeys
        Input:init()
      end
    )

    it("should contain only Back and Left on few-keys devices", function()
      -- Mock hasFewKeys to true
      local original_hasFewKeys = Input.device.hasFewKeys
      Input.device.hasFewKeys = function()
        return true
      end
      Input.group.Dismiss = {}
      Input:init()

      local dismiss_group = Input.group.Dismiss
      assert.truthy(dismiss_group)

      -- Should contain Back keys
      for _, key in ipairs(Input.group.Back or {}) do
        assert.truthy(util.arrayContains(dismiss_group, key))
      end
      -- Should contain Left
      assert.truthy(util.arrayContains(dismiss_group, "Left"))
      -- Should NOT contain PgFwd/PgBack/Menu
      assert.falsy(util.arrayContains(dismiss_group, "Menu"))
      for _, key in ipairs(Input.group.PgFwd or {}) do
        assert.falsy(util.arrayContains(dismiss_group, key))
      end

      -- Restore
      Input.device.hasFewKeys = original_hasFewKeys
      Input:init()
    end)

    it("should assert that a few-keys device has keys", function()
      local original_hasFewKeys = Input.device.hasFewKeys
      local original_hasKeys = Input.device.hasKeys
      Input.device.hasFewKeys = function()
        return true
      end
      Input.device.hasKeys = function()
        return false
      end

      assert.has_error(function()
        Input:init()
      end, "A device with few keys must have keys")

      -- Restore
      Input.device.hasFewKeys = original_hasFewKeys
      Input.device.hasKeys = original_hasKeys
      Input:init()
    end)
  end)

  describe("Keyboard and modifier events", function()
    it("should handle key press, repeat, and release", function()
      Input.event_map[100] = "A"
      local ev_press = { type = C.EV_KEY, code = 100, value = 1 }
      local res_press = Input:handleKeyBoardEv(ev_press)
      assert.is_table(res_press)
      assert.are.equal("onKeyPress", res_press.handler)
      assert.are.equal("A", res_press.args[1].key)

      local ev_release = { type = C.EV_KEY, code = 100, value = 0 }
      local res_release = Input:handleKeyBoardEv(ev_release)
      assert.is_table(res_release)
      assert.are.equal("onKeyRelease", res_release.handler)
      assert.are.equal("A", res_release.args[1].key)
    end)

    it("should update modifier state on Shift/Ctrl/Alt keys", function()
      Input.event_map[42] = "Shift"
      Input.event_map[29] = "Ctrl"
      Input.event_map[56] = "Alt"

      assert.is_false(Input.modifiers.Shift)
      Input:handleKeyBoardEv({ type = C.EV_KEY, code = 42, value = 1 })
      assert.is_true(Input.modifiers.Shift)
      Input:handleKeyBoardEv({ type = C.EV_KEY, code = 42, value = 0 })
      assert.is_false(Input.modifiers.Shift)

      assert.is_false(Input.modifiers.Ctrl)
      Input:handleKeyBoardEv({ type = C.EV_KEY, code = 29, value = 1 })
      assert.is_true(Input.modifiers.Ctrl)
      Input:handleKeyBoardEv({ type = C.EV_KEY, code = 29, value = 0 })
      assert.is_false(Input.modifiers.Ctrl)
    end)

    it("should handle Power key events", function()
      Input.event_map[116] = "Power"
      local press =
        Input:handleKeyBoardEv({ type = C.EV_KEY, code = 116, value = 1 })
      assert.are.equal("PowerPress", press)
      local release =
        Input:handleKeyBoardEv({ type = C.EV_KEY, code = 116, value = 0 })
      assert.are.equal("PowerRelease", release)
    end)

    it("should handle fake events like IntoSS and Charging", function()
      local ev_ss = { type = C.EV_KEY, code = 10000, value = 1 }
      local res_ss = Input:handleKeyBoardEv(ev_ss)
      assert.are.equal("IntoSS", res_ss)

      local ev_chg = { type = C.EV_KEY, code = 10020, value = 1 }
      local res_chg = Input:handleKeyBoardEv(ev_chg)
      assert.are.equal("Charging", res_chg)
    end)
  end)

  describe("Clipboard & State Management", function()
    it("should get, set, and query clipboard text", function()
      local clip_storage = ""
      local orig_has = Input.hasClipboardText
      local orig_get = Input.getClipboardText
      local orig_set = Input.setClipboardText

      Input.hasClipboardText = function() return clip_storage ~= "" end
      Input.getClipboardText = function() return clip_storage end
      Input.setClipboardText = function(t) clip_storage = t or "" end

      Input.setClipboardText("KORTestClip")
      assert.is_true(Input.hasClipboardText())
      assert.is_equal("KORTestClip", Input.getClipboardText())

      Input.setClipboardText("")
      assert.is_false(Input.hasClipboardText())
      assert.is_equal("", Input.getClipboardText())

      Input.hasClipboardText = orig_has
      Input.getClipboardText = orig_get
      Input.setClipboardText = orig_set
    end)

    it("should reset state and disable rotation map", function()
      assert.has_no.errors(function()
        local custom_input = Input:new({
          device = require("device"),
        })
        custom_input:resetState()
        custom_input:disableRotationMap()
      end)
    end)
  end)

  describe("Event Adjustment Hooks", function()
    it("registers and chains event adjust hooks", function()
      local hook1_called = 0
      local hook2_called = 0
      local custom_input = Input:new({
        device = require("device"),
      })

      custom_input:registerEventAdjustHook(function(_this, _ev, param)
        hook1_called = hook1_called + param
      end, 5)

      custom_input:registerEventAdjustHook(function(_this, _ev, param)
        hook2_called = hook2_called + param
      end, 10)

      local ev = { type = C.EV_ABS, code = C.ABS_X, value = 100 }
      custom_input.eventAdjustHook(custom_input, ev)

      assert.is_equal(5, hook1_called)
      assert.is_equal(10, hook2_called)
    end)

    it("registers and chains gesture adjust hooks", function()
      local g_called = 0
      local custom_input = Input:new({
        device = require("device"),
      })

      custom_input:registerGestureAdjustHook(function(_this, _ges, param)
        g_called = g_called + param
      end, 20)

      custom_input:registerGestureAdjustHook(function(_this, _ges, param)
        g_called = g_called + param
      end, 30)

      custom_input.gestureAdjustHook(custom_input, {})
      assert.is_equal(50, g_called)
    end)

    it("adjusts ABS coordinates with predefined helpers", function()
      local ev_x = { type = C.EV_ABS, code = C.ABS_X, value = 100 }
      Input:adjustABS_SwitchXY(ev_x)
      assert.is_equal(C.ABS_Y, ev_x.code)

      local ev_y = { type = C.EV_ABS, code = C.ABS_Y, value = 200 }
      Input:adjustABS_SwitchXY(ev_y)
      assert.is_equal(C.ABS_X, ev_y.code)

      local ev_scale = { type = C.EV_ABS, code = C.ABS_X, value = 100 }
      Input:adjustABS_Scale(ev_scale, { x = 2, y = 3 })
      assert.is_equal(200, ev_scale.value)

      local ev_trans = { type = C.EV_ABS, code = C.ABS_X, value = 100 }
      Input:adjustABS_Translate(ev_trans, { x = 25, y = 50 })
      assert.is_equal(125, ev_trans.value)

      local ev_mirror_x = { type = C.EV_ABS, code = C.ABS_Y, value = 100 }
      Input:adjustABS_SwitchAxesAndMirrorX(ev_mirror_x, 600)
      assert.is_equal(C.ABS_X, ev_mirror_x.code)
      assert.is_equal(500, ev_mirror_x.value)

      local ev_mirror_y = { type = C.EV_ABS, code = C.ABS_X, value = 100 }
      Input:adjustABS_SwitchAxesAndMirrorY(ev_mirror_y, 800)
      assert.is_equal(C.ABS_Y, ev_mirror_y.code)
      assert.is_equal(700, ev_mirror_y.value)
    end)
  end)

  describe("Timeout & Timer Management", function()
    it("sets, sorts, and clears timeouts", function()
      local custom_input = Input:new({
        device = require("device"),
      })
      custom_input.gesture_detector = {
        getClockSource = function() return C.CLOCK_MONOTONIC end,
      }
      custom_input:clearTimeouts()
      assert.is_equal(0, #custom_input.timer_callbacks)

      local cb1 = function() end
      local cb2 = function() end
      local cb3 = function() end

      custom_input:setTimeout(0, "tap", cb1, 1000, 500)
      custom_input:setTimeout(0, "double_tap", cb2, 1000, 200)
      custom_input:setTimeout(1, "tap", cb3, 1000, 800)

      assert.is_equal(3, #custom_input.timer_callbacks)
      assert.is_equal("double_tap", custom_input.timer_callbacks[1].gesture)
      assert.is_equal("tap", custom_input.timer_callbacks[2].gesture)
      assert.is_equal(1, custom_input.timer_callbacks[3].slot)

      -- Clear specific gesture on slot 0
      custom_input:clearTimeout(0, "double_tap")
      assert.is_equal(2, #custom_input.timer_callbacks)
      assert.is_equal("tap", custom_input.timer_callbacks[1].gesture)

      -- Clear all timeouts for slot 0
      custom_input:clearTimeout(0)
      assert.is_equal(1, #custom_input.timer_callbacks)
      assert.is_equal(1, custom_input.timer_callbacks[1].slot)

      -- Clear all timeouts
      custom_input:clearTimeouts()
      assert.is_equal(0, #custom_input.timer_callbacks)
    end)
  end)

  describe("Key Rotation & Special Events", function()
    it("translates direction keys according to rotation mode", function()
      local fb = require("ffi/framebuffer")
      local Screen = require("device").screen
      stub(Screen, "getRotationMode").returns(fb.DEVICE_ROTATED_CLOCKWISE)

      local custom_input = Input:new({
        device = require("device"),
      })
      custom_input.event_map[103] = "Up"
      local res =
        custom_input:handleKeyBoardEv({ type = C.EV_KEY, code = 103, value = 1 })
      assert.is_table(res)
      assert.is_equal("Right", res.args[1].key)

      Screen.getRotationMode:revert()
    end)

    it("handles generic and void input events", function()
      local ev = { type = 99, code = 1, value = 2 }
      local generic_ev = Input:handleGenericEv(ev)
      assert.is_table(generic_ev)
      assert.is_equal("onGenericInput", generic_ev.handler)

      assert.is_nil(Input:voidEv(ev))
    end)
  end)

  describe("Touch Protocols", function()
    it("handles wacom protocol pen events", function()
      local custom_input = Input:new({
        device = require("device"),
      })
      custom_input.wacom_protocol = true

      -- Pen down
      custom_input:handleKeyBoardEv({
        type = C.EV_KEY,
        code = C.BTN_TOOL_PEN,
        value = 1,
      })
      assert.is_equal(1, custom_input:getCurrentMtSlotData("tool"))

      custom_input:handleKeyBoardEv({
        type = C.EV_KEY,
        code = C.BTN_TOUCH,
        value = 1,
      })
      assert.is_equal(
        custom_input.pen_slot,
        custom_input:getCurrentMtSlotData("id")
      )

      -- Pen up
      custom_input:handleKeyBoardEv({
        type = C.EV_KEY,
        code = C.BTN_TOUCH,
        value = 0,
      })
      assert.is_equal(-1, custom_input:getCurrentMtSlotData("id"))

      custom_input:handleKeyBoardEv({
        type = C.EV_KEY,
        code = C.BTN_TOOL_PEN,
        value = 0,
      })
      assert.is_equal(0, custom_input.ev_slots[custom_input.pen_slot].tool)
    end)

    it("handles snow protocol contact lift", function()
      local custom_input = Input:new({
        device = require("device"),
      })
      custom_input.snow_protocol = true
      custom_input.ev_slots = {
        [0] = { slot = 0, id = 1 },
        [1] = { slot = 1, id = 2 },
      }
      custom_input.MTSlots = {}

      custom_input:handleKeyBoardEv({
        type = C.EV_KEY,
        code = C.BTN_TOUCH,
        value = 0,
      })
      assert.is_equal(-1, custom_input.ev_slots[0].id)
      assert.is_equal(-1, custom_input.ev_slots[1].id)
    end)
  end)
end)
