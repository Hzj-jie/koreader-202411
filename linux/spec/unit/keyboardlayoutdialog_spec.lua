describe("KeyboardLayoutDialog UI component", function()
    local Device, KeyboardLayoutDialog

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Device = require("device")
        KeyboardLayoutDialog = require("ui/widget/keyboardlayoutdialog")
    end)

    before_each(function()
        _G.G_reader_settings = {
            readTableRef = function(self, key)
                return { "en_US" }
            end,
            read = function(self, key)
                return "en_US"
            end,
        }
    end)

    it("should instantiate without crashing when parent and keyboard state are mocked", function()
        local mock_keyboard = {
            lang_to_keyboard_layout = {
                en_US = {},
                fr_FR = {},
            },
            getKeyboardLayout = function()
                return "en_US"
            end,
        }
        local mock_parent = {
            keyboard = mock_keyboard,
        }
        local mock_keyboard_state = {}

        local dialog
        assert.has_no.errors(function()
            dialog = KeyboardLayoutDialog:new({
                parent = mock_parent,
                keyboard_state = mock_keyboard_state,
            })
        end)
        assert.is_not_nil(dialog)
        assert.is_not_nil(dialog.title_bar)
    end)

    it("should initialize, run callbacks with self, and clear parent ref on close", function()
        local mock_keyboard = {
            getKeyboardLayout = function()
                return "en_US"
            end,
            setKeyboardLayout = spy.new(function() end),
            lang_to_keyboard_layout = { en_US = {}, fr_FR = {} },
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
        local close_calls = {}
        UIManager.close = function(self, widget)
            table.insert(close_calls, { self, widget })
        end

        -- Find "Switch to layout" button
        local switch_btn = dialog.button_table.buttons_layout[1][2]
        assert.is_not_nil(switch_btn)

        -- Mock selection
        dialog.radio_button_table.checked_button = { provider = "fr_FR" }

        switch_btn.callback()

        -- Verify setKeyboardLayout was called with "fr_FR"
        assert.spy(mock_keyboard.setKeyboardLayout).was_called_with(mock_keyboard, "fr_FR")
        -- Verify UIManager:close was called with dialog (self)
        assert.are.equal(1, #close_calls)
        assert.are.equal(UIManager, close_calls[1][1])
        assert.are.equal(dialog, close_calls[1][2])

        -- Trigger onClose to verify leak fix
        dialog:onClose()
        assert.is_nil(mock_parent.keyboard_layout_dialog)

        UIManager.close = old_close
    end)

    it("should instantiate with only one language layout in lang_to_keyboard_layout", function()
        local mock_keyboard = {
            lang_to_keyboard_layout = {
                en_US = {},
            },
            getKeyboardLayout = function()
                return "en_US"
            end,
        }
        local mock_parent = {
            keyboard = mock_keyboard,
        }
        local mock_keyboard_state = {}

        local dialog = KeyboardLayoutDialog:new({
            parent = mock_parent,
            keyboard_state = mock_keyboard_state,
        })
        assert.is_not_nil(dialog)
        assert.is_not_nil(dialog.radio_button_table)
        -- The table has one row containing one radio button
        assert.is.same(1, #dialog.radio_button_table.radio_buttons)
    end)

    it("should throw error when lang_to_keyboard_layout is empty", function()
        local mock_keyboard = {
            lang_to_keyboard_layout = {},
            getKeyboardLayout = function()
                return nil
            end,
        }
        local mock_parent = {
            keyboard = mock_keyboard,
        }
        local mock_keyboard_state = {}

        assert.has.errors(function()
            KeyboardLayoutDialog:new({
                parent = mock_parent,
                keyboard_state = mock_keyboard_state,
            })
        end)
    end)

    it("should throw error when lang_to_keyboard_layout is nil", function()
        local mock_keyboard = {
            lang_to_keyboard_layout = nil,
            getKeyboardLayout = function()
                return nil
            end,
        }
        local mock_parent = {
            keyboard = mock_keyboard,
        }
        local mock_keyboard_state = {}

        assert.has.errors(function()
            KeyboardLayoutDialog:new({
                parent = mock_parent,
                keyboard_state = mock_keyboard_state,
            })
        end)
    end)
end)
