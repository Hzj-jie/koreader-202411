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

  it("should copy and delete shortcuts", function()
    Terminal.shortcuts = {
      { text = "Test", commands = "echo hi" },
    }
    Terminal.saveShortcuts = function() end
    Terminal.manageShortcuts = function() end

    Terminal:copyCommands({ text = "Test", commands = "echo hi" })
    assert.are.equal(2, #Terminal.shortcuts)
    assert.are.equal("Test (copy)", Terminal.shortcuts[2].text)

    Terminal:deleteShortcut({ text = "Test (copy)", commands = "echo hi" })
    assert.are.equal(1, #Terminal.shortcuts)
  end)

  it("should dump entries to file", function()
    local tmp = os.tmpname()
    Terminal.dump_file = tmp
    Terminal:dump({ "command: echo hello", "hello" })

    local f = io.open(tmp, "r")
    assert.is_not_nil(f)
    local content = f:read("*a")
    f:close()
    assert.is_true(content:find("hello") ~= nil)

    os.remove(tmp)
  end)

  it("should build main menu item structure", function()
    local menu_items = {}
    Terminal:addToMainMenu(menu_items)
    assert.is_table(menu_items.legacy_terminal)
    assert.is_function(menu_items.legacy_terminal.callback)
  end)
end)
