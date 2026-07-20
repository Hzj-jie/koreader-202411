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

  local function cleanup()
    if UIManager and UIManager._window_stack then
      while #UIManager._window_stack > 0 do
        local w = UIManager._window_stack[#UIManager._window_stack].widget
        UIManager:close(w)
      end
    end
    if FileManager then
      FileManager.instance = nil
    end
  end

  before_each(cleanup)
  after_each(cleanup)

  it(
    "should trigger callbacks for all key-bar buttons in Terminal input dialog",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      assert.is_not_nil(terminal)

      -- Close any initial loading info/notifications
      while #UIManager._window_stack > 1 do
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end

      -- Mock spawning and shell communication methods to operate in-memory
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
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
        [1] = "↹", -- tab
        [2] = "/", -- slash (back slash)
        [3] = "Esc", -- Esc
        [4] = "Ctrl", -- Ctrl
        [5] = "Ctrl-C", -- Ctrl-C
        [6] = "⇧", -- Up
        [7] = "⇩", -- Down
        [8] = "☰", -- Menu
        [9] = "✕", -- Exit
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
    end
  )

  it(
    "should handle CJK characters and wrap them correctly based on visual width",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      assert.is_not_nil(terminal)

      -- Close any initial loading info/notifications
      while #UIManager._window_stack > 1 do
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end

      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
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
      assert.is.same({ "中", "文", "文", "件", "名", "\n" }, line1)

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
      -- "中" (cols 0-2), first "文" (cols 2-4).
      -- Target 3 is inside first "文", snaps to index 2 (first "文") due to containment-based snapping in getCharposAtVisualColumn.
      -- So charpos should become 2.
      term_widget:moveCursorUp()
      assert.is.same(2, term_widget.charpos)

      -- Move DOWN:
      -- Current visual col on line 1 (start at 1):
      -- "中" (2) -> 2 (since cursor is at index 2, which is start of first "文").
      -- Target visual col is 2.
      -- Line 2: {"a", "b", "c", " ", ...} (start at 7).
      -- "a" (1), "b" (1) -> 2.
      -- So it should land on index 9 (after "b", which is "c" index).
      term_widget:moveCursorDown()
      assert.is.same(9, term_widget.charpos)

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should not crash when restoring an out-of-bounds or nil saved cursor position",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:interpretAnsiSeq("abc")
      assert.is.same(4, term_widget.charpos)

      -- 1. Test out-of-bounds saved position (should clamp to #charlist + 1 = 4)
      term_widget.store_pos_dec = 100
      term_widget:interpretAnsiSeq("\0278")
      assert.is.same(4, term_widget.charpos)

      -- 2. Test nil saved position (should not change charpos)
      term_widget.store_pos_dec = nil
      term_widget:interpretAnsiSeq("\0278")
      assert.is.same(4, term_widget.charpos)

      -- 3. Print more text to verify it works normally
      term_widget:interpretAnsiSeq("d")
      assert.is.same("d", term_widget.charlist[4])
      assert.is.same(5, term_widget.charpos)

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should not allow charpos to go out of bounds and create nil holes when writing text",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:interpretAnsiSeq("a")
      -- Set charpos way out of bounds of current buffer
      term_widget.charpos = 5000

      -- Write a character
      term_widget:interpretAnsiSeq("x")

      -- Verify that the gap was padded with spaces and x was written at 5000
      assert.is.same("a", term_widget.charlist[1])
      assert.is.same(" ", term_widget.charlist[2])
      assert.is.same("x", term_widget.charlist[5000])
      assert.is.same(5000, #term_widget.charlist)
      assert.is.same(5001, term_widget.charpos)

      -- Verify table.concat doesn't crash
      local success, result = pcall(table.concat, term_widget.charlist)
      assert.is_true(success, "table.concat failed: " .. tostring(result))
      assert.is.same("a" .. string.rep(" ", 4998) .. "x", result)

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should correctly update charpos and avoid nil holes during scrollRegionUp",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:resize(10, 10)
      term_widget:formatTerminal(true)

      -- 1. Setup lines: 3 lines of 5 characters
      term_widget:interpretAnsiSeq("12345\nabcde\nABCDE\n")

      -- 2. Enable scroll region
      term_widget.scroll_region_top = 1
      term_widget.scroll_region_bottom = 2
      term_widget.scroll_region_line = 2

      -- Move cursor to line 3 (index 18, which is the \n of ABCDE\n)
      term_widget.charpos = 18

      -- 3. Trigger scroll up
      term_widget:scrollRegionUp(1)

      -- Verify charpos was correctly shifted (18 - 11 = 7)
      assert.is.same(7, term_widget.charpos)

      -- Verify table.concat doesn't crash (i.e. no nil holes were created)
      local success, result = pcall(table.concat, term_widget.charlist)
      assert.is_true(success, "table.concat failed: " .. tostring(result))

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should avoid nil holes and not crash table.concat during scrollRegionDown",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:resize(10, 10)
      term_widget:formatTerminal(true)

      -- 1. Setup lines: 5 lines of 5 characters
      term_widget:interpretAnsiSeq("12345\nabcde\nABCDE\n67890\nXYZWZ\n")

      -- Verify buffer is correct
      local success, result = pcall(table.concat, term_widget.charlist)
      assert.is_true(success)

      -- 2. Enable scroll region on lines 2 to 4
      term_widget.scroll_region_top = 2
      term_widget.scroll_region_bottom = 4
      term_widget.scroll_region_line = 2 -- cursor is at top of region (line 2)

      -- Move cursor to line 2 (index 12, start of abcde)
      term_widget.charpos = 12

      -- 3. Trigger scroll down
      term_widget:scrollRegionDown(1)

      -- Verify table.concat doesn't crash (i.e. no nil holes were created)
      local success_concat, result_concat =
        pcall(table.concat, term_widget.charlist)
      assert.is_true(
        success_concat,
        "table.concat failed: " .. tostring(result_concat)
      )

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should delete the bottom line of the scroll region and shift other lines correctly during scrollRegionDown",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:resize(10, 10)
      term_widget:formatTerminal(true)

      -- 1. Setup lines: 5 lines of 5 characters
      term_widget:interpretAnsiSeq("12345\nabcde\nABCDE\n67890\nXYZWZ\n")

      -- Verify buffer is correct
      local success, result = pcall(table.concat, term_widget.charlist)
      assert.is_true(success)

      -- 2. Enable scroll region on lines 2 to 4
      term_widget.scroll_region_top = 2
      term_widget.scroll_region_bottom = 4
      term_widget.scroll_region_line = 2 -- cursor is at top of region (line 2)

      -- Move cursor to line 2 (index 12, start of abcde)
      term_widget.charpos = 12

      -- 3. Trigger scroll down
      term_widget:scrollRegionDown(1)

      local result_concat = table.concat(term_widget.charlist)

      -- Verify that the bottom line of scroll region (Line 4: 67890) was deleted,
      -- NOT the line below it (Line 5: XYZWZ).
      local lines = {}
      for line in result_concat:gmatch("[^\n]+") do
        table.insert(lines, line)
      end


      assert.is.same("12345     ", lines[1])
      assert.is.same("          ", lines[2])
      assert.is.same(" abcde    ", lines[3])
      assert.is.same(" ABCDE    ", lines[4])
      assert.is.same(" XYZWZ    ", lines[5])

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should allow moving cursor right up to the end of line (before newline)",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      term_widget:interpretAnsiSeq("abc\n")

      -- Buffer is {"a", "b", "c", "\n"}, length 4.
      -- Let's position cursor at index 1 (before "a") manually.
      term_widget:moveCursorToCharPos(1)

      -- Move right (should go to 2, before "b")
      term_widget:rightChar(true)
      assert.is.same(2, term_widget.charpos)

      -- Move right (should go to 3, before "c")
      term_widget:rightChar(true)
      assert.is.same(3, term_widget.charpos)

      -- Move right (should go to 4, before "\n", i.e. after "c")
      term_widget:rightChar(true)
      assert.is.same(4, term_widget.charpos)

      -- Move right (should NOT move, since index 4 is "\n")
      term_widget:rightChar(true)
      assert.is.same(4, term_widget.charpos)

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should handle invalid UTF-8 characters and binary data gracefully without crashing",
    function()
      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      terminal:onTerminalStart(filemanager.menu)
      UIManager:forceRepaint()

      local input_dialog = UIManager._window_stack[2].widget
      local term_widget = input_dialog._input_widget

      -- Send invalid UTF-8 sequence and binary bytes (e.g. \xff\xfe\x00)
      local success, err = pcall(function()
        term_widget:interpretAnsiSeq("hello \xff\xfe\000 world")
      end)
      assert.is_true(success, "interpretAnsiSeq crashed: " .. tostring(err))

      UIManager:close(input_dialog)
      filemanager:onClose()
    end
  )

  it(
    "should not crash during initialization when Device is mocked to use PhysicalKeyboard",
    function()
      local Device = require("device")
      -- 1. Backup Device:isTouchDevice
      local orig_isTouchDevice = Device.isTouchDevice
      Device.isTouchDevice = function()
        return false
      end

      -- 2. Mock Device:hasDPad to return false to force PhysicalKeyboard loading
      local orig_hasDPad = Device.hasDPad
      Device.hasDPad = function()
        return false
      end

      -- 3. Force reload inputtext and terminputtext
      package.loaded["ui/widget/inputtext"] = nil
      package.loaded["plugins/terminal.koplugin/terminputtext"] = nil

      local filemanager = FileManager:new({
        dimen = Screen:getSize(),
        root_path = "spec/unit/data",
      })

      local terminal = filemanager.terminal
      terminal.spawnShell = function(self)
        self.is_shell_open = true
        return true
      end
      terminal.receive = function(self)
        return ""
      end
      terminal.transmit = function(self) end
      terminal.refresh = function(self) end

      -- 4. Start terminal (should use TermInputText with PhysicalKeyboard)
      local success, err = pcall(function()
        terminal:onTerminalStart(filemanager.menu)
      end)

      -- 5. Restore mocks and packages
      Device.isTouchDevice = orig_isTouchDevice
      Device.hasDPad = orig_hasDPad
      package.loaded["ui/widget/inputtext"] = nil
      package.loaded["plugins/terminal.koplugin/terminputtext"] = nil

      assert.is_true(
        success,
        "onTerminalStart crashed under PhysicalKeyboard: " .. tostring(err)
      )

      if success then
        local input_dialog = UIManager._window_stack[2].widget
        UIManager:close(input_dialog)
      end
      filemanager:onClose()
    end
  )

  it("should monitor ScrollTextWidget instantiations in Terminal", function()
    local ScrollTextWidget = require("ui/widget/scrolltextwidget")
    local spy_new = spy.on(ScrollTextWidget, "new")

    local filemanager = FileManager:new({
      dimen = Screen:getSize(),
      root_path = "spec/unit/data",
    })

    local terminal = filemanager.terminal
    terminal.spawnShell = function(self)
      self.is_shell_open = true
      return true
    end
    terminal.receive = function(self)
      return ""
    end
    terminal.transmit = function(self) end
    terminal.refresh = function(self) end

    -- Start terminal
    terminal:onTerminalStart(filemanager.menu)
    UIManager:forceRepaint()

    local input_dialog = UIManager._window_stack[2].widget
    local term_widget = input_dialog._input_widget

    local initial_calls = #spy_new.calls

    -- Simulate keystrokes or ansi output
    term_widget:interpretAnsiSeq("a")
    term_widget:interpretAnsiSeq("b")
    term_widget:interpretAnsiSeq("c")

    local after_calls = #spy_new.calls

    -- We expect 0 calls because it's reused now
    assert.are.equal(0, after_calls - initial_calls)

    UIManager:close(input_dialog)
    filemanager:onClose()
    spy_new:revert()
  end)

  it("should call ioctl TIOCSWINSZ with correct dimensions in _updateWinSize", function()
    local ffi = require("ffi")
    local original_ffi_C = ffi.C

    local ioctl_called = false
    local ioctl_fd, ioctl_req, ioctl_ws

    local mock_C = setmetatable({
      ioctl = function(fd, req, ws)
        ioctl_called = true
        ioctl_fd = fd
        ioctl_req = tonumber(req)
        local ws_struct = ffi.cast("struct winsize*", ws)
        ioctl_ws = {
          ws_row = tonumber(ws_struct.ws_row),
          ws_col = tonumber(ws_struct.ws_col),
        }
        return 0
      end
    }, {
      __index = original_ffi_C
    })

    local mock_ffi = setmetatable({
      C = mock_C
    }, {
      __index = ffi
    })

    package.loaded["ffi"] = mock_ffi
    package.loaded["plugins/terminal.koplugin/main"] = nil

    local Terminal = require("plugins/terminal.koplugin/main")

    package.loaded["ffi"] = ffi

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end
      }
    }
    local terminal = Terminal:new({
      ui = mock_ui
    })
    terminal.ptmx = 42

    terminal:_updateWinSize(80, 24)

    assert.is_true(ioctl_called)
    assert.is.same(42, ioctl_fd)
    assert.is.same(0x5414, ioctl_req)
    assert.is_not_nil(ioctl_ws)
    assert.is.same(24, ioctl_ws.ws_row)
    assert.is.same(80, ioctl_ws.ws_col)

    package.loaded["plugins/terminal.koplugin/main"] = nil
  end)
end)
