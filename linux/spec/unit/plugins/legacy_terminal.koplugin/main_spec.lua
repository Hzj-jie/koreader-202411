describe("Legacy Terminal plugin main module", function()
  local LegacyTerminal
  local UIManager
  local Trapper

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    LegacyTerminal = require("plugins/legacy_terminal.koplugin/main")
    UIManager = require("ui/uimanager")
    Trapper = require("ui/trapper")
  end)

  describe("Initialization & Main Menu", function()
    it("should initialize LegacyTerminal plugin instance", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      assert.is_table(term)
      assert.are.equal("legacy_terminal", term.name)
    end)

    it("should register dispatcher actions", function()
      local registered = {}
      local Dispatcher = require("dispatcher")
      local orig_registerAction = Dispatcher.registerAction
      Dispatcher.registerAction = function(self, name, action)
        registered[name] = action
      end
      finally(function()
        Dispatcher.registerAction = orig_registerAction
      end)

      if type(LegacyTerminal.onDispatcherRegisterActions) == "function" then
        LegacyTerminal:onDispatcherRegisterActions()
      end
      assert.is_not_nil(registered["show_terminal"])
      assert.are.equal("TerminalStart", registered["show_terminal"].event)
    end)

    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      local menu_items = {}
      term:addToMainMenu(menu_items)
      assert.is_table(menu_items)
    end)
  end)

  describe("Command Formatting", function()
    it("ensures newline after commands", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })

      assert.are.equal("ls -la\n", term:ensureWhitelineAfterCommands("ls -la"))
      assert.are.equal(
        "ls -la\n",
        term:ensureWhitelineAfterCommands("ls -la\n")
      )
      assert.are.equal(
        "echo 1\necho 2\n",
        term:ensureWhitelineAfterCommands("echo 1\necho 2\n")
      )
    end)
  end)

  describe("Shortcuts Management", function()
    local orig_show
    local shown_widgets

    before_each(function()
      shown_widgets = {}
      orig_show = UIManager.show
      UIManager.show = function(self, widget)
        table.insert(shown_widgets, widget)
      end
      LegacyTerminal.shortcuts = {}
    end)

    after_each(function()
      UIManager.show = orig_show
      LegacyTerminal.shortcuts = {}
    end)

    it("manages and sorts shortcuts alphabetically", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      term.shortcuts = {
        { text = "Z_command", commands = "echo z" },
        { text = "A_command", commands = "echo a" },
      }

      term:manageShortcuts()
      assert.are.equal("A_command", term.shortcuts[1].text)
      assert.are.equal("Z_command", term.shortcuts[2].text)
      assert.is_not_nil(term.shortcuts_dialog)
      assert.is_not_nil(term.shortcuts_menu)
    end)

    it("copies a shortcut and saves shortcuts list", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      term.shortcuts = {
        { text = "Check IP", commands = "ifconfig" },
      }

      term:copyCommands({ text = "Check IP", commands = "ifconfig" })
      assert.are.equal(2, #term.shortcuts)
      assert.are.equal("Check IP (copy)", term.shortcuts[2].text)
      assert.are.equal("ifconfig", term.shortcuts[2].commands)
    end)

    it("deletes a shortcut matching text and commands", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      term.shortcuts = {
        { text = "Keep me", commands = "uptime" },
        { text = "Remove me", commands = "rm /tmp/foo" },
      }

      term:deleteShortcut({ text = "Remove me", commands = "rm /tmp/foo" })
      assert.are.equal(1, #term.shortcuts)
      assert.are.equal("Keep me", term.shortcuts[1].text)
    end)

    it("opens hold menu dialog for editable shortcuts", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
      })
      term.shortcuts = {
        { text = "Test", commands = "echo test" },
      }

      local handled = term:onMenuHoldShortcuts({
        nr = 1,
        text = "Test",
        commands = "echo test",
        editable = true,
        deletable = true,
      })
      assert.is_true(handled)
      local shown_dialog = shown_widgets[#shown_widgets]
      assert.is_not_nil(shown_dialog)
      assert.is_not_nil(shown_dialog.buttons)
    end)
  end)

  describe("Execution & Popen Handling", function()
    it("handles completed command execution with dump output", function()
      local ffiUtil = require("ffi/util")
      local pid = tostring(ffiUtil.getpid())
      local tmp_dump = os.tmpname() .. "_" .. pid .. ".txt"

      local shown_widgets = {}
      local orig_show = UIManager.show
      UIManager.show = function(self, widget)
        table.insert(shown_widgets, widget)
      end

      local orig_popen = Trapper.dismissablePopen
      Trapper.dismissablePopen = function(self, cmd, wait_msg)
        return true, "hello from stdout"
      end

      finally(function()
        UIManager.show = orig_show
        Trapper.dismissablePopen = orig_popen
        os.remove(tmp_dump)
      end)

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
        dump_file = tmp_dump,
        command = "echo hello",
        source = "terminal",
      })

      term:execute()

      local h = io.open(tmp_dump, "r")
      assert.is_not_nil(h)
      local content = h:read("*a")
      h:close()
      assert.is_true(content:find("hello from stdout") ~= nil)
    end)

    it("handles canceled command execution", function()
      local shown_widgets = {}
      local orig_show = UIManager.show
      UIManager.show = function(self, widget)
        table.insert(shown_widgets, widget)
      end

      local orig_popen = Trapper.dismissablePopen
      Trapper.dismissablePopen = function(self, cmd, wait_msg)
        return false, nil
      end

      finally(function()
        UIManager.show = orig_show
        Trapper.dismissablePopen = orig_popen
      end)

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local term = LegacyTerminal:new({
        ui = mock_ui,
        command = "sleep 10",
        source = "terminal",
      })

      term:execute()
      local viewer = shown_widgets[#shown_widgets]
      assert.is_not_nil(viewer)
    end)
  end)
end)
