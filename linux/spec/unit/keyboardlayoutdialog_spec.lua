describe("KeyboardLayoutDialog", function()
    local KeyboardLayoutDialog
    setup(function()
        require("commonrequire")
        KeyboardLayoutDialog = require("ui/widget/keyboardlayoutdialog")
    end)

    it("should initialize, run callbacks with self, and clear parent ref on close", function()
        local mock_keyboard = {
            getKeyboardLayout = function() return "en" end,
            setKeyboardLayout = spy.new(function() end),
            lang_to_keyboard_layout = { en = {} },
        }
        local mock_parent = {
            keyboard = mock_keyboard,
            keyboard_layout_dialog = nil,
        }

        local dialog
        dialog = KeyboardLayoutDialog:new({
            parent = mock_parent,
            keyboard_state = {},
        })
        mock_parent.keyboard_layout_dialog = dialog

        -- Check init worked
        assert.is_not_nil(dialog.radio_button_table)
        assert.is_not_nil(dialog.button_table)

        -- Mock UIManager:close
        local UIManager = require("ui/uimanager")
        local old_close = UIManager.close
        UIManager.close = spy.new(function() end)

        -- Find "Switch to layout" button
        local switch_btn = dialog.button_table.buttons_layout[1][2]
        assert.is_not_nil(switch_btn)

        -- Mock selection
        dialog.radio_button_table.checked_button = { provider = "fr" }

        switch_btn.callback()

        -- Verify setKeyboardLayout was called with "fr"
        assert.spy(mock_keyboard.setKeyboardLayout).was_called_with(mock_keyboard, "fr")
        -- Verify UIManager:close was called with dialog (self)
        assert.spy(UIManager.close).was_called_with(UIManager, dialog)

        -- Trigger onClose to verify leak fix
        dialog:onClose()
        assert.is_nil(mock_parent.keyboard_layout_dialog)

        UIManager.close = old_close
    end)
end)
