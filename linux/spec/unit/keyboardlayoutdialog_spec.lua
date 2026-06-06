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
end)
