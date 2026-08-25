describe("Terminal plugin button tap integration", function()
  local UIManager, Screen, FileManager

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
      local success = pcall(table.concat, term_widget.charlist)
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
      local success = pcall(table.concat, term_widget.charlist)
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
      assert.is.same("abcde     ", lines[3])
      assert.is.same("ABCDE     ", lines[4])
      assert.is.same("XYZWZ     ", lines[5])

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

  it(
    "should call ioctl TIOCSWINSZ with correct dimensions in _updateWinSize",
    function()
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
        end,
      }, {
        __index = original_ffi_C,
      })

      local mock_ffi = setmetatable({
        C = mock_C,
      }, {
        __index = ffi,
      })

      package.loaded["ffi"] = mock_ffi
      package.loaded["plugins/terminal.koplugin/main"] = nil

      local Terminal = require("plugins/terminal.koplugin/main")

      package.loaded["ffi"] = ffi

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local terminal = Terminal:new({
        ui = mock_ui,
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
    end
  )

  it("should exercise all main menu callbacks and dialogs", function()
    local Terminal = require("plugins/terminal.koplugin/main")
    local mock_menu = { updateItems = stub() }
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local terminal = Terminal:new({ ui = mock_ui })
    local menu_items = {}
    terminal:addToMainMenu(menu_items)

    local sub_items = menu_items.terminal.sub_item_table
    assert.is_table(sub_items)

    local show_stub = stub(UIManager, "show")
    local close_stub = stub(UIManager, "close")

    -- 1. About
    sub_items[1].callback()
    assert.stub(show_stub).was.called(1)

    -- 2. Open session text_func
    assert.is_string(sub_items[2].text_func())

    -- 3. End session
    assert.is_boolean(sub_items[3].enabled_func())
    sub_items[3].callback(mock_menu)

    -- 4. Font size
    assert.is_string(sub_items[4].text_func())
    sub_items[4].callback(mock_menu)
    local font_spin = show_stub.calls[#show_stub.calls].vals[2]
    assert.is_table(font_spin)
    font_spin.value = 16
    font_spin.callback(font_spin)
    assert.are.equal(16, G_reader_settings:read("terminal_font_size"))

    -- 5. Buffer size
    assert.is_string(sub_items[5].text_func())
    sub_items[5].callback(mock_menu)
    local buf_spin = show_stub.calls[#show_stub.calls].vals[2]
    assert.is_table(buf_spin)
    buf_spin.value = 24
    buf_spin.callback(buf_spin)
    assert.are.equal(24, G_reader_settings:read("terminal_buffer_size"))

    -- 6. Shell executable
    assert.is_string(sub_items[6].text_func())
    sub_items[6].callback(mock_menu)
    local shell_dlg = show_stub.calls[#show_stub.calls].vals[2]
    assert.is_table(shell_dlg)

    -- Cancel button
    shell_dlg.buttons[1][1].callback()
    assert.stub(close_stub).was.called(1)

    -- Default button
    shell_dlg.buttons[1][2].callback()
    assert.stub(close_stub).was.called(2)

    -- Save button
    shell_dlg.buttons[1][3].callback()

    show_stub:revert()
    close_stub:revert()
  end)

  it("should test generateInputDialog callbacks and enter/strike handlers", function()
    local Terminal = require("plugins/terminal.koplugin/main")
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local terminal = Terminal:new({ ui = mock_ui })
    terminal.input_face = require("ui/font"):getFace("smallinfont", 14)

    local transmitted = {}
    terminal.transmit = function(self, chars)
      table.insert(transmitted, chars)
    end

    local dialog = terminal:generateInputDialog()
    assert.is_table(dialog)
    terminal.input_dialog = dialog

    -- Test enter_callback
    dialog.enter_callback()
    assert.are.equal("\r", transmitted[#transmitted])

    -- Test strike_callback
    dialog.strike_callback("a")
    assert.are.equal("a", transmitted[#transmitted])

    -- Test strike_callback with Ctrl
    terminal.ctrl = true
    dialog.strike_callback("c")
    assert.are.equal("\003", transmitted[#transmitted])

    -- Test strike_callback newline
    dialog.strike_callback("\n")
    assert.are.equal("\r\n", transmitted[#transmitted])

    -- Test cancel button (MultiConfirmBox)
    local show_stub = stub(UIManager, "show")
    local close_stub = stub(UIManager, "close")
    local cancel_btn = dialog.button_table.buttons_layout[1][9]
    cancel_btn.callback()
    assert.stub(show_stub).was.called(1)
    local confirm_box = show_stub.calls[1].vals[2]
    assert.is_table(confirm_box)

    -- Close choice
    confirm_box.choice1_callback()
    assert.stub(close_stub).was.called(1)

    -- Quit choice
    confirm_box.choice2_callback()
    assert.stub(close_stub).was.called(2)

    show_stub:revert()
    close_stub:revert()
  end)

  it("should test TermInputText buffer operations and ANSI sequences", function()
    local TermInputText = require("plugins/terminal.koplugin/terminputtext")
    local widget = TermInputText:new({
      width = 400,
      height = 300,
      scroll = true,
      face = require("ui/font"):getFace("smallinfont", 14),
      parent = { setDirty = function() end },
    })

    -- 1. Test saveBuffer and restoreBuffer
    widget:interpretAnsiSeq("First Buffer Text")
    assert.are.equal("First Buffer Text", table.concat(widget.charlist))

    widget:saveBuffer("alternate_buffer")
    assert.are.equal(0, #widget.charlist)
    assert.are.equal(1, widget.charpos)

    widget:interpretAnsiSeq("Alternate Buffer Text")
    assert.are.equal("Alternate Buffer Text", table.concat(widget.charlist))

    widget:restoreBuffer("alternate_buffer")
    assert.are.equal("First Buffer Text", table.concat(widget.charlist))

    -- 2. Test trimBuffer
    widget.min_buffer_size = 5
    widget:interpretAnsiSeq("\nline 1\nline 2\nline 3\n")
    widget:trimBuffer(10)
    assert.is_true(#widget.charlist <= 20)

    -- 3. Test ANSI sequences: Colors, Cursor movement, Clearing
    -- SGR color
    widget:interpretAnsiSeq("\027[31;1mRed Bold\027[0m")
    -- Cursor UP / DOWN / LEFT / RIGHT
    widget:interpretAnsiSeq("\027[2A\027[2B\027[3C\027[3D")
    -- CUP cursor position
    widget:interpretAnsiSeq("\027[2;5H")
    -- ED erase in display
    widget:interpretAnsiSeq("\027[2J")
    -- EL erase in line
    widget:interpretAnsiSeq("\027[0K\027[1K\027[2K")
    -- DECSET / DECRST alternate screen
    widget:interpretAnsiSeq("\027[?1049h")
    widget:interpretAnsiSeq("\027[?1049l")

    -- 4. Test scrolling & line navigation
    widget:upLine()
    widget:downLine()
    widget:scrollUp()
    widget:scrollDown()

    -- 5. Test escape Y row col positioning
    widget:interpretAnsiSeq(string.format("\027Y%c%c", 32 + 2, 32 + 5))

    -- 6. Test save and restore cursor pos via DEC and SCO escape codes
    widget:interpretAnsiSeq("Hello World")
    widget:interpretAnsiSeq("\0277") -- DEC save
    widget:interpretAnsiSeq("\027[2D")
    widget:interpretAnsiSeq("\0278") -- DEC restore
    widget:interpretAnsiSeq("\027[s") -- SCO save
    widget:interpretAnsiSeq("\027[3D")
    widget:interpretAnsiSeq("\027[u") -- SCO restore

    -- 7. Test identify callback \027Z
    local identified = nil
    widget.strike_callback = function(seq) identified = seq end
    widget:interpretAnsiSeq("\027Z")
    assert.are.equal("\027/K", identified)
    widget.strike_callback = nil

    -- 8. Test alternate keypad
    widget:interpretAnsiSeq("\027=")
    widget:interpretAnsiSeq("Alternate Keypad Mode")
    widget:interpretAnsiSeq("\027>")

    -- 9. Test reverse line feed and scroll regions
    widget:interpretAnsiSeq("\027[1;10r")
    widget:interpretAnsiSeq("\027I")
    widget:interpretAnsiSeq("\027[r") -- reset scroll region

    -- 10. Test line navigation and deletion methods
    widget:goToStartOfLine(true)
    widget:goToEndOfLine(true)
    widget:goToStartOfLine(false)
    widget:goToEndOfLine(false)
    widget:delToEndOfLine()
    widget:delToStartOfLine()
    widget:delChar()
    assert.is_true(widget:onTapTextBox())

    -- 11. Test addChars with wrap=false and wide CJK replacement
    widget.wrap = false
    widget:addChars("Wide replacement: 中文字符测试")
    widget.wrap = true
    widget:addChars("\r\nNew line text\b\b")
  end)

  it("should test Terminal menu items and settings dialogs", function()
    local Terminal = require("plugins/terminal.koplugin/main")
    local inst = Terminal:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })
    inst:init()

    local menu_items = {}
    inst:addToMainMenu(menu_items)
    local t_menu = menu_items.terminal
    assert.is_table(t_menu)
    assert.is_table(t_menu.sub_item_table)

    local shown_dialogs = {}
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function(self_uim, d) table.insert(shown_dialogs, d) end
    UIManager.close = function() end

    -- 1. About dialog
    local about_item = t_menu.sub_item_table[1]
    assert.are.equal("About terminal emulator", about_item.text)
    about_item.callback()
    assert.is_true(#shown_dialogs >= 1)

    -- 2. Open terminal session
    local open_item = t_menu.sub_item_table[2]
    local open_text = open_item.text_func()
    assert.is_string(open_text)

    -- 3. End terminal session
    local end_item = t_menu.sub_item_table[3]
    local is_enabled = end_item.enabled_func()
    assert.is_boolean(is_enabled)
    end_item.callback({ updateItems = function() end })

    -- 4. Font size SpinWidget
    local font_item = t_menu.sub_item_table[4]
    local font_text = font_item.text_func()
    assert.is_string(font_text)
    font_item.callback({ updateItems = function() end })
    local font_spin = shown_dialogs[#shown_dialogs]
    if font_spin and font_spin.callback then
      font_spin.value = 16
      font_spin.callback(font_spin)
      assert.are.equal(16, G_reader_settings:read("terminal_font_size"))
    end

    -- 5. Buffer size SpinWidget
    local buffer_item = t_menu.sub_item_table[5]
    local buffer_text = buffer_item.text_func()
    assert.is_string(buffer_text)
    buffer_item.callback({ updateItems = function() end })
    local buffer_spin = shown_dialogs[#shown_dialogs]
    if buffer_spin and buffer_spin.callback then
      buffer_spin.value = 24
      buffer_spin.callback(buffer_spin)
      assert.are.equal(24, G_reader_settings:read("terminal_buffer_size"))
    end

    -- 6. Shell executable dialog
    local shell_item = t_menu.sub_item_table[6]
    local shell_text = shell_item.text_func()
    assert.is_string(shell_text)
    shell_item.callback({ updateItems = function() end })
    local shell_dialog = shown_dialogs[#shown_dialogs]
    assert.is_table(shell_dialog)
    if shell_dialog and shell_dialog.buttons then
      local btn_row = shell_dialog.buttons[1]
      -- Cancel button
      btn_row[1].callback()
      -- Default button
      btn_row[2].callback()
      -- Save button with valid shell
      inst.shell_dialog = {
        getInputText = function() return "sh" end,
      }
      btn_row[3].callback()
      -- Save button with non-executable shell
      inst.shell_dialog = {
        getInputText = function() return "non_existent_shell_xyz_123" end,
      }
      btn_row[3].callback()
    end

    -- 7. Test helper methods
    assert.is_string(inst:getDefaultShellExecutable())
    assert.is_boolean(inst:isExecutable("sh"))
    assert.is_false(inst:isExecutable("non_existent_binary_xyz_123"))

    -- 8. Test lifecycle methods
    inst:onExit()
    inst:onClose()

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should test Terminal input dialog strike and enter callbacks", function()
    local Terminal = require("plugins/terminal.koplugin/main")
    local inst = Terminal:new({
      ui = { menu = { registerToMainMenu = function() end } },
    })
    inst:init()

    local transmitted = {}
    inst.transmit = function(self, s) table.insert(transmitted, s) end
    inst.receive = function() return "" end
    inst.refresh = function() end

    local dialog = inst:generateInputDialog()
    assert.is_table(dialog)

    -- Test enter_callback
    dialog.enter_callback()
    assert.are.equal("\r", transmitted[#transmitted])

    -- Test strike_callback normal
    dialog.strike_callback("a")
    assert.are.equal("a", transmitted[#transmitted])

    -- Test strike_callback with newline
    dialog.strike_callback("\n")
    assert.are.equal("\r\n", transmitted[#transmitted])

    -- Test strike_callback with ctrl active
    inst.ctrl = true
    dialog.strike_callback("c")
    assert.are.equal("\003", transmitted[#transmitted])
    assert.is_false(inst.ctrl)
  end)

  it("should register dispatcher actions for terminal plugin", function()
    local Terminal = require("plugins/terminal.koplugin/main")
    if type(Terminal.onDispatcherRegisterActions) == "function" then
      Terminal:onDispatcherRegisterActions()
    end
  end)

  it("should initialize terminputtext widget safely", function()
    local TermInputText = dofile("plugins/terminal.koplugin/terminputtext.lua")
    assert.is_table(TermInputText)
  end)
end)
