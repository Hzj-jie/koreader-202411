describe("QRClipboard plugin", function()
  local QRClipboard, Device, UIManager

  setup(function()
    require("commonrequire")
    QRClipboard = require("plugins/qrclipboard.koplugin/main")
    Device = require("device")
    UIManager = require("ui/uimanager")
  end)

  local orig_getClipboardText, orig_show
  local shown_widgets

  before_each(function()
    shown_widgets = {}
    orig_getClipboardText = Device.input.getClipboardText
    orig_show = UIManager.show

    UIManager.show = function(_self, widget)
      table.insert(shown_widgets, widget)
    end
  end)

  after_each(function()
    Device.input.getClipboardText = orig_getClipboardText
    UIManager.show = orig_show
  end)

  it("should initialize and register to main menu", function()
    local registered_plugin = nil
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self, plugin)
          registered_plugin = plugin
        end,
      },
    }

    local plugin = QRClipboard:new({ ui = mock_ui })
    assert.is_table(plugin)
    assert.are.equal("qrclipboard", plugin.name)
    assert.is_false(plugin.is_doc_only)
    assert.are.equal(plugin, registered_plugin)
  end)

  it("should add qrclipboard item to main menu and show QRMessage with clipboard text", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local plugin = QRClipboard:new({ ui = mock_ui })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)
    assert.is_table(menu_items.qrclipboard)
    assert.are.equal("QR from clipboard", menu_items.qrclipboard.text)
    assert.is_function(menu_items.qrclipboard.callback)

    Device.input.getClipboardText = function()
      return "https://koreader.rocks"
    end

    menu_items.qrclipboard.callback()

    assert.are.equal(1, #shown_widgets)
    local qrmessage = shown_widgets[1]
    assert.is_table(qrmessage)
    assert.are.equal("https://koreader.rocks", qrmessage.text)
    assert.are.equal(Device.screen:getWidth(), qrmessage.width)
    assert.are.equal(Device.screen:getHeight(), qrmessage.height)
  end)

  it("should handle empty clipboard text string", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local plugin = QRClipboard:new({ ui = mock_ui })

    local menu_items = {}
    plugin:addToMainMenu(menu_items)

    Device.input.getClipboardText = function()
      return ""
    end

    menu_items.qrclipboard.callback()

    assert.are.equal(1, #shown_widgets)
    local qrmessage = shown_widgets[1]
    assert.is_table(qrmessage)
    assert.are.equal("", qrmessage.text)
  end)
end)
