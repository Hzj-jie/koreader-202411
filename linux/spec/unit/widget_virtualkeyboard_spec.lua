describe("VirtualKeyboard component", function()
    local Device, VirtualKeyboard, Event, UIManager

    setup(function()
        require("commonrequire")
        package.unloadAll()
        local device = require("device")
        require("document/canvascontext"):init(device)

        Device = require("device")
        VirtualKeyboard = require("ui/widget/virtualkeyboard")
        Event = require("ui/event")
        UIManager = require("ui/uimanager")
    end)

    before_each(function()
        UIManager._window_stack = {}
        _G.G_reader_settings = {
            read = function(self, key)
                return nil
            end,
            nilOrTrue = function(self, key)
                return true
            end,
            isTrue = function(self, key)
                return false
            end,
            isFalse = function(self, key)
                return false
            end,
            readTableRef = function(self, key)
                return { "en" }
            end,
        }
    end)

    after_each(function()
        UIManager._window_stack = {}
    end)

    it("should instantiate and forward character inputs to target inputbox", function()
        local added_chars = nil
        local del_char_called = false

        local mock_inputbox = {
            addChars = function(self, char)
                added_chars = char
            end,
            delChar = function(self)
                del_char_called = true
            end,
        }

        local vk = VirtualKeyboard:new({
            inputbox = mock_inputbox,
            width = 600,
            height = 300,
        })

        assert.is_not_nil(vk)

        -- Test direct delegation methods
        vk:addChar("x")
        assert.is.same("x", added_chars)

        vk:delChar()
        assert.is_true(del_char_called)
    end)

    it("should trigger inputbox actions when virtual keys are tapped", function()
        local added_chars = {}
        local mock_inputbox = {
            addChars = function(self, char)
                table.insert(added_chars, char)
            end,
        }

        local vk = VirtualKeyboard:new({
            inputbox = mock_inputbox,
            width = 600,
            height = 300,
        })

        -- Let's locate the 'a' key in layout
        local key_a = nil
        for _, row in ipairs(vk.layout) do
            for _, key_widget in ipairs(row) do
                if key_widget.key == "a" or key_widget.label == "a" then
                    key_a = key_widget
                    break
                end
            end
            if key_a then
                break
            end
        end

        assert.is_not_nil(key_a)

        -- Tap the 'a' key
        -- Mock Haptic feedback call on Device
        Device.performHapticFeedback = function() end

        key_a:onTapSelect(true) -- skip flash for unit testing ease

        assert.is.same({ "a" }, added_chars)
    end)

    it("should not trigger assertion under normal conditions", function()
        local mock_inputbox = {
            addChars = function() end,
            delChar = function() end,
            scheduleRepaint = function() end,
        }
        local vk = VirtualKeyboard:new({
            inputbox = mock_inputbox,
            width = 600,
            height = 300,
        })

        assert.has_no.errors(function()
            vk:setVisibility(true)
        end)

        assert.has_no.errors(function()
            vk:setVisibility(false)
        end)
    end)

    it("should trigger assertion when showing multiple instances", function()
        local mock_inputbox = {
            addChars = function() end,
            delChar = function() end,
            scheduleRepaint = function() end,
        }
        local vk1 = VirtualKeyboard:new({
            inputbox = mock_inputbox,
            width = 600,
            height = 300,
        })
        local vk2 = VirtualKeyboard:new({
            inputbox = mock_inputbox,
            width = 600,
            height = 300,
        })

        vk1:setVisibility(true)

        assert.has.errors(function()
            vk2:setVisibility(true)
        end, "Multiple VirtualKeyboard instances detected!")

        -- Cleanup
        vk1:setVisibility(false)
        UIManager:close(vk2)
    end)
end)
