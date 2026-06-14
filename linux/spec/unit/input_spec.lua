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

        it("should contain Back, PgFwd, PgBack and Menu on normal devices", function()
            -- Ensure device is treated as normal (not few keys)
            local original_hasFewKeys = Input.device.hasFewKeys
            Input.device.hasFewKeys = function() return false end
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
        end)

        it("should contain only Back and Left on few-keys devices", function()
            -- Mock hasFewKeys to true
            local original_hasFewKeys = Input.device.hasFewKeys
            Input.device.hasFewKeys = function() return true end
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
            Input.device.hasFewKeys = function() return true end
            Input.device.hasKeys = function() return false end

            assert.has_error(function()
                Input:init()
            end, "A device with few keys must have keys")

            -- Restore
            Input.device.hasFewKeys = original_hasFewKeys
            Input.device.hasKeys = original_hasKeys
            Input:init()
        end)
    end)

end)
