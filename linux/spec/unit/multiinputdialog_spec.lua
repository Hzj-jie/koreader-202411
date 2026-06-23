describe("MultiInputDialog widget", function()
    local MultiInputDialog, InputText, InputDialog, UIManager
    setup(function()
        require("commonrequire")
        MultiInputDialog = require("ui/widget/multiinputdialog")
        InputText = require("ui/widget/inputtext")
        InputDialog = require("ui/widget/inputdialog")
        UIManager = require("ui/uimanager")
    end)

    it("should close all input fields when closed", function()
        local Event = require("ui/event")

        local calls = 0
        local original_onClose = InputText.onClose
        InputText.onClose = function(self)
            calls = calls + 1
            return original_onClose(self)
        end

        local dialog = MultiInputDialog:new({
            title = "Test",
            fields = {
                { text = "1" },
                { text = "2" },
                { text = "3" },
            },
        })

        dialog:broadcastEvent(Event:new("Show"))
        dialog:broadcastEvent(Event:new("Close"))

        -- 1 (measurement dummy) + 1 (discarded main dummy) + 3 (fields) = 5
        assert.are.equal(5, calls)

        InputText.onClose = original_onClose
    end)

    it("should toggle password visibility when checkbox is tapped", function()
        local Event = require("ui/event")
        local Screen = require("device").screen

        local dialog = MultiInputDialog:new({
            title = "Password Test",
            fields = {
                { text = "123", text_type = "password" },
            },
            width = Screen:getWidth(),
        })

        UIManager:show(dialog)
        UIManager:forceRepaint()

        local input_field = dialog.input_fields[1]
        assert.is.same("password", input_field.text_type)
        assert.truthy(input_field._check_button)
        assert.is.same(false, input_field._check_button.checked)

        -- Get coordinates of the checkbox
        local cb_dimen = input_field._check_button:getSize()

        -- Simulate tap on the checkbox
        local Geom = require("ui/geometry")
        local tap_pos = Geom:new({
            x = cb_dimen.x + cb_dimen.w / 2,
            y = cb_dimen.y + cb_dimen.h / 2,
            w = 0,
            h = 0,
        })
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = tap_pos
        })

        dialog:handleEvent(tap_event:asUserInput())

        -- Expect it to be toggled
        local new_input_field = dialog.input_fields[1]
        assert.is.same("text", new_input_field.text_type)
        assert.is.same(true, new_input_field._check_button.checked)

        UIManager:close(dialog)
    end)

    it("should toggle password visibility on unfocused field without focusing it", function()
        local Event = require("ui/event")
        local Screen = require("device").screen

        local dialog = MultiInputDialog:new({
            title = "Password Test 2",
            fields = {
                { text = "123", input_type = "number" },
                { text = "456", text_type = "password" },
            },
            width = Screen:getWidth(),
        })

        UIManager:show(dialog)
        UIManager:forceRepaint()

        local input_field1 = dialog.input_fields[1]
        local input_field2 = dialog.input_fields[2]



        assert.truthy(input_field1.focused)
        assert.falsy(input_field2.focused)

        -- Get coordinates of the second checkbox
        local cb_dimen2 = input_field2._check_button:getSize()
        local Geom = require("ui/geometry")
        local tap_pos = Geom:new({
            x = cb_dimen2.x + cb_dimen2.w / 2,
            y = cb_dimen2.y + cb_dimen2.h / 2,
            w = 0,
            h = 0,
        })
        local tap_event = Event:new("Gesture", {
            ges = "tap",
            pos = tap_pos
        })

        dialog:handleEvent(tap_event:asUserInput())

        -- Manually trigger re-layout (simulating screen resize / keyboard height change)
        -- to verify that state (text_type) is preserved across recreation.
        dialog:onKeyboardHeightChanged()

        -- Expect field 2 to be toggled
        local active_field2 = dialog.input_fields[2]
        assert.is_not.equal(input_field2, active_field2)
        assert.is.same("text", active_field2.text_type)
        assert.is.same(true, active_field2._check_button.checked)

        -- Check focus (expecting change)
        assert.falsy(dialog.input_fields[1].focused)
        assert.truthy(dialog.input_fields[2].focused)

        UIManager:close(dialog)
    end)
    it("should preserve moved offset across recreation", function()
        local Screen = require("device").screen
        local dialog = MultiInputDialog:new({
            title = "Test Movable Multi",
            fields = {
                { text = "1" },
            },
            width = Screen:getWidth(),
        })

        UIManager:show(dialog)
        UIManager:forceRepaint()

        assert.truthy(dialog.movable)
        local initial_offset = dialog.movable:getMovedOffset()
        assert.is.same(0, initial_offset.x)
        assert.is.same(0, initial_offset.y)

        -- Move it
        dialog.movable:_moveBy(50, 100)
        local moved_offset = dialog.movable:getMovedOffset()
        assert.is.same(50, moved_offset.x)
        assert.is.same(100, moved_offset.y)

        -- Recreate
        dialog:onKeyboardHeightChanged()

        -- Verify offset is preserved
        local new_offset = dialog.movable:getMovedOffset()
        assert.is.same(50, new_offset.x)
        assert.is.same(100, new_offset.y)

        UIManager:close(dialog)
    end)
end)
