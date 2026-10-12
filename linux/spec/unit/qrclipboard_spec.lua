-- luacheck: ignore 122
describe("QRClipboard widget tests", function()
  local Device, QRClipboard, UIManager
  local orig_getClipboardText
  local mock_ui
  local shown_widgets

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Device = require("device")
    QRClipboard = require("plugins/qrclipboard.koplugin/main")
    UIManager = require("ui/uimanager")
    orig_getClipboardText = Device.input.getClipboardText
  end)

  teardown(function()
    Device.input.getClipboardText = orig_getClipboardText
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    shown_widgets = {}
    UIManager.show = function(_, widget)
      table.insert(shown_widgets, widget)
    end

    mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
  end)

  it("should register to main menu in init", function()
    local registered_target = nil
    mock_ui.menu.registerToMainMenu = function(_, target)
      registered_target = target
    end

    local plugin = QRClipboard:new({ ui = mock_ui })
    plugin:init()
    assert.are.equal(plugin, registered_target)
  end)

  it("should add qrclipboard entry to main menu", function()
    local plugin = QRClipboard:new({ ui = mock_ui })
    local menu_items = {}
    plugin:addToMainMenu(menu_items)

    assert.is_not_nil(menu_items.qrclipboard)
    assert.is_string(menu_items.qrclipboard.text)
    assert.is_function(menu_items.qrclipboard.callback)
  end)

  it(
    "should show QRMessage with clipboard text when clipboard is non-empty",
    function()
      local plugin = QRClipboard:new({ ui = mock_ui })
      local menu_items = {}
      plugin:addToMainMenu(menu_items)

      Device.input.getClipboardText = function()
        return "https://koreader.rocks"
      end

      menu_items.qrclipboard.callback()
      assert.are.equal(1, #shown_widgets)
      assert.are.equal("https://koreader.rocks", shown_widgets[1].text)
    end
  )
end)
