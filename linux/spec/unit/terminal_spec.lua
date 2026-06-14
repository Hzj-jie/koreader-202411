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

    it("should handle CJK characters and wrap them correctly based on visual width", function()
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

        terminal.spawnShell = function(self)
            self.is_shell_open = true
            return true
        end
        terminal.receive = function(self) return "" end
        terminal.transmit = function(self) end
        terminal.refresh = function(self) end

        -- Start terminal plugin
        terminal:onTerminalStart(filemanager.menu)
        UIManager:forceRepaint()

        local input_dialog = UIManager._window_stack[2].widget
        local term_widget = input_dialog._input_widget
        assert.is_not_nil(term_widget)

        -- Resize to 10x10 for predictable wrapping
        term_widget:resize(10, 10)
        term_widget:formatTerminal(true)

        -- Write CJK text (8 visual cols) + "ab" (2 visual cols) = 10 visual cols
        term_widget:interpretAnsiSeq("中文文件名ab")

        -- Line 1 should have CJK + \n
        -- "中文文件名" has 5 chars: 中, 文, 文, 件, 名.
        -- Visual width: 10.
        -- So it fits exactly.
        -- "ab" (written in same call) should have wrapped to line 2.
        local line1 = {}
        for i = 1, 6 do
            table.insert(line1, term_widget.charlist[i])
        end
        assert.is.same({"中", "文", "文", "件", "名", "\n"}, line1)

        -- "a" and "b" should be on line 2
        assert.is.same("a", term_widget.charlist[7])
        assert.is.same("b", term_widget.charlist[8])

        -- Write "c" (1 col), should append to line 2
        term_widget:interpretAnsiSeq("c")

        -- Line 2 should have "a", "b", "c"
        assert.is.same("a", term_widget.charlist[7])
        assert.is.same("b", term_widget.charlist[8])
        assert.is.same("c", term_widget.charlist[9])

        -- Cursor should be at index 10 (after "c" on line 2)
        assert.is.same(10, term_widget.charpos)

        -- Move UP:
        -- Current visual col on line 2 (start at 7):
        -- "a" (1), "b" (1), "c" (1) -> 3. (Cursor is after "c", so at visual col 3).
        -- Target visual col is 3.
        -- Line 1: {"中", "文", "文", "件", "名", "\n"} (start at 1).
        -- "中" (cols 0-2), "文" (cols 2-4).
        -- Target 3 is in middle of first "文", snaps to 4 (index 3, which is second "文").
        -- So charpos should become 3.
        term_widget:moveCursorUp()
        assert.is.same(3, term_widget.charpos)

        -- Move DOWN:
        -- Current visual col on line 1 (start at 1):
        -- "中" (2), first "文" (2) -> 4 (before second "文").
        -- Target visual col is 4.
        -- Line 2: {"a", "b", "c", " ", ...} (start at 7).
        -- "a" (1), "b" (1), "c" (1), " " (1) -> 4.
        -- So it should land on index 11 (after "c" and one space).
        term_widget:moveCursorDown()
        assert.is.same(11, term_widget.charpos)

        UIManager:close(input_dialog)
        filemanager:onClose()
    end)
end)
