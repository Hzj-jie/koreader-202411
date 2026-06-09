describe("Terminal plugin button tap integration", function()
    local UIManager, Screen, FileManager, original_refresh

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
        UIManager = require("ui/uimanager")
        Screen = require("device").screen
        FileManager = require("apps/filemanager/filemanager")
    end)

    before_each(function()
        UIManager._window_stack = {}
    end)

    after_each(function()
        UIManager._window_stack = {}
    end)

    it("should trigger callbacks for all key-bar buttons in Terminal input dialog", function()
        local filemanager = FileManager:new{
            dimen = Screen:getSize(),
            root_path = "spec/unit/data",
        }

        local terminal = filemanager.terminal
        assert.is_not_nil(terminal)

        -- Close any initial loading info/notifications
        while #UIManager._window_stack > 1 do
            UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
        end

        -- Mock spawning and shell communication methods to operate in-memory
        terminal.spawnShell = function(self)
            self.is_shell_open = true
            return true
        end
        terminal.receive = function(self) return "" end
        terminal.transmit = function(self) end
        terminal.refresh = function(self) end

        -- Start terminal plugin (which shows the input dialog)
        terminal:onTerminalStart(filemanager.menu)

        -- Force layout/paint pass so that all widgets compute their sizes and locations
        UIManager:forceRepaint()

        -- Verify dialog was successfully shown on stack (index 2, since FileManager is index 1)
        assert.is.same(3, #UIManager._window_stack) -- FileManager, InputDialog, VirtualKeyboard
        local input_dialog = UIManager._window_stack[2].widget
        assert.is_not_nil(input_dialog)

        -- Retrieve the buttons row from button table
        local button_table = input_dialog.button_table
        assert.is_not_nil(button_table)
        local button_row = button_table.buttons_layout[1]
        assert.is_not_nil(button_row)
        assert.is.same(9, #button_row)

        local Event = require("ui/event")
        local Geom = require("ui/geometry")

        -- Map expected index to button description/text
        local expected_buttons = {
            [1] = "↹",     -- tab
            [2] = "/",     -- slash (back slash)
            [3] = "Esc",   -- Esc
            [4] = "Ctrl",  -- Ctrl
            [5] = "Ctrl-C",-- Ctrl-C
            [6] = "⇧",     -- Up
            [7] = "⇩",     -- Down
            [8] = "☰",     -- Menu
            [9] = "✕",     -- Exit
        }

        for idx, expected_text in ipairs(expected_buttons) do
            local btn = button_row[idx]
            assert.is_not_nil(btn)
            assert.is.same(expected_text, btn.text)

            -- Mock the button callback to record the tap
            local callback_called = false
            local original_callback = btn.callback
            btn.callback = function()
                callback_called = true
            end

            -- Simulate tapping the center of the button
            local cx = btn.dimen.x + btn.dimen.w / 2
            local cy = btn.dimen.y + btn.dimen.h / 2
            local tap_event = Event:new("Gesture", {
                ges = "tap",
                pos = Geom:new({ x = cx, y = cy }),
                time = require("ui/time").monotonic(),
            }):asUserInput()

            UIManager:userInput(tap_event)

            assert.is_true(callback_called)

            -- Restore original callback
            btn.callback = original_callback
        end

        -- Clean up
        UIManager:close(input_dialog)
        filemanager:onClose()
    end)
end)
