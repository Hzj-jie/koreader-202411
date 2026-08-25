describe("Legacy Terminal plugin main module", function()
  local Terminal

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Terminal = require("plugins/legacy_terminal.koplugin/main")
  end)

  it("should initialize Legacy Terminal plugin instance", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    Terminal.ui = mock_ui
    Terminal:init()

    assert.is_table(Terminal)
    assert.is_string(Terminal.command)
    assert.is_table(Terminal.shortcuts)
  end)

  it("should format commands with trailing newline", function()
    assert.are.equal(
      "ls -la\n",
      Terminal:ensureWhitelineAfterCommands("ls -la")
    )
    assert.are.equal("pwd\n", Terminal:ensureWhitelineAfterCommands("pwd\n"))
  end)

  it("should manage shortcuts and generate items table with page actions", function()
    local UIManager = require("ui/uimanager")
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local shown_widgets = {}
    UIManager.show = function(self_uim, w) table.insert(shown_widgets, w) end
    UIManager.close = function() end

    Terminal.shortcuts = {
      { text = "Bravo", commands = "echo b" },
      { text = "Alpha", commands = "echo a" },
    }
    Terminal.items_per_page = 4

    Terminal:manageShortcuts()
    assert.are.equal("Alpha", Terminal.shortcuts[1].text)
    assert.are.equal("Bravo", Terminal.shortcuts[2].text)
    assert.is_table(Terminal.shortcuts_dialog)
    assert.is_table(Terminal.shortcuts_menu)

    -- Test close_callback
    if Terminal.shortcuts_menu.close_callback then
      Terminal.shortcuts_menu.close_callback()
    end

    -- Test empty shortcuts list
    Terminal.shortcuts = {}
    Terminal:manageShortcuts()

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should handle hold menu on shortcut items: edit name, edit commands, copy, delete", function()
    local UIManager = require("ui/uimanager")
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local shown_widgets = {}
    UIManager.show = function(self_uim, w) table.insert(shown_widgets, w) end
    UIManager.close = function() end

    Terminal.shortcuts = {
      { text = "Test Cmd", commands = "ls -la" },
    }
    Terminal.shortcuts_dialog = { name = "dialog" }

    local item = { nr = 1, text = "Test Cmd", commands = "ls -la", editable = true, deletable = true }
    local dummy_menu = { _manager = Terminal }

    local handled = Terminal.onMenuHoldShortcuts(dummy_menu, item)
    assert.is_true(handled)

    local btn_dialog = shown_widgets[#shown_widgets]
    assert.is_table(btn_dialog)

    -- 1. Test Edit name callback
    btn_dialog.buttons[1][1].callback()
    local edit_name_dialog = shown_widgets[#shown_widgets]
    assert.is_table(edit_name_dialog)
    if edit_name_dialog.buttons then
      edit_name_dialog.getInputText = function() return "Renamed Cmd" end
      edit_name_dialog.buttons[1][2].callback()
      item.text = "Renamed Cmd"
      assert.are.equal("Renamed Cmd", Terminal.shortcuts[1].text)
    end

    -- 2. Test Edit commands callback
    btn_dialog.buttons[1][2].callback()
    local edit_cmd_dialog = shown_widgets[#shown_widgets]
    assert.is_table(edit_cmd_dialog)
    if edit_cmd_dialog.buttons then
      edit_cmd_dialog.getInputText = function() return "echo updated" end
      edit_cmd_dialog.buttons[1][2].callback()
      item.commands = "echo updated"
      assert.are.equal("echo updated", Terminal.shortcuts[1].commands)
    end

    -- 3. Test Copy callback
    btn_dialog.buttons[2][1].callback()
    assert.are.equal(2, #Terminal.shortcuts)

    -- 4. Test Delete callback
    btn_dialog.buttons[2][2].callback()
    assert.are.equal(1, #Terminal.shortcuts)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should handle terminal input dialog, save to shortcut, and execution", function()
    local UIManager = require("ui/uimanager")
    local Trapper = require("ui/trapper")
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local orig_popen = Trapper.dismissablePopen
    local shown_widgets = {}
    UIManager.show = function(self_uim, w) table.insert(shown_widgets, w) end
    UIManager.close = function() end

    -- Successful execution mock
    Trapper.dismissablePopen = function(self_trapper, cmd, wait_msg)
      return true, "Execution Output Line 1\nOutput Line 2"
    end

    Terminal.shortcuts = {}
    Terminal:onTerminalStart() -- Should call terminal() when shortcuts is empty

    local term_dialog = Terminal.input
    assert.is_table(term_dialog)

    -- Test Shortcuts button
    term_dialog.buttons[1][2].callback()

    -- Test Save button (prompt for name)
    term_dialog.getInputText = function() return "pwd" end
    term_dialog.buttons[1][3].callback()
    local name_prompt = shown_widgets[#shown_widgets]
    assert.is_table(name_prompt)
    if name_prompt.buttons then
      name_prompt.buttons[1][1].callback() -- Cancel
      name_prompt.getInputText = function() return "Current Dir" end
      name_prompt.buttons[1][2].callback() -- Save
      assert.are.equal(1, #Terminal.shortcuts)
      assert.are.equal("Current Dir", Terminal.shortcuts[1].text)
    end

    -- Test Execute button (from terminal source)
    Terminal.source = "terminal"
    term_dialog.getInputText = function() return "echo test" end
    term_dialog.buttons[1][4].callback()
    local text_viewer = shown_widgets[#shown_widgets]
    assert.is_table(text_viewer)
    if text_viewer.buttons_table then
      local row = text_viewer.buttons_table[1]
      row[1].callback() -- Back
      row[2].callback() -- Shortcuts
      row[3].callback() -- Close
    end

    -- Test Execute from shortcut source with canceled execution
    Terminal.source = "shortcut"
    Terminal.command = "sleep 10"
    Trapper.dismissablePopen = function() return false, nil end
    Terminal:execute()
    text_viewer = shown_widgets[#shown_widgets]
    assert.is_table(text_viewer)
    if text_viewer.buttons_table then
      local row = text_viewer.buttons_table[1]
      row[1].callback() -- Back
      row[2].callback() -- Terminal
      row[3].callback() -- Close
    end

    -- Test Cancel button
    term_dialog.buttons[1][1].callback()

    UIManager.show = orig_show
    UIManager.close = orig_close
    Trapper.dismissablePopen = orig_popen
  end)

  it("should dump entries to file and handle invalid dump paths", function()
    local tmp = os.tmpname()
    Terminal.dump_file = tmp
    Terminal:dump({ "command: echo hello", "hello" })

    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.is_true(content:find("hello") ~= nil)
    os.remove(tmp)

    -- Invalid dump path handling
    Terminal.dump_file = "/non/existent/directory/12345/dump.txt"
    Terminal:dump({ "failed dump" })
  end)

  it("should build main menu item structure", function()
    local menu_items = {}
    Terminal:addToMainMenu(menu_items)
    assert.is_table(menu_items.legacy_terminal)
    assert.is_function(menu_items.legacy_terminal.callback)
    menu_items.legacy_terminal.callback()
  end)
end)
