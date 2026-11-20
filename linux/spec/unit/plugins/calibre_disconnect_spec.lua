describe("Calibre wireless disconnect", function()
  local Calibre, CalibreWireless, UIManager, mock_socket, remove_zmq_stub

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Calibre = require("plugins/calibre.koplugin/main")
    CalibreWireless = require("plugins/calibre.koplugin/wireless")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    mock_socket = {
      stop = spy.new(function() end),
    }
    CalibreWireless.calibre_socket = mock_socket
    CalibreWireless.calibre_messagequeue = "mock_zmq"
    remove_zmq_stub = stub(UIManager, "removeZMQ")
  end)

  after_each(function()
    CalibreWireless.calibre_socket = nil
    CalibreWireless.calibre_messagequeue = nil
    remove_zmq_stub:revert()
  end)

  it("disconnects active wireless connection from closeWirelessConnection", function()
    local plugin = Calibre:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })

    plugin:closeWirelessConnection()

    assert.spy(mock_socket.stop).was_called(1)
    assert.is_nil(CalibreWireless.calibre_socket)
    assert.is_nil(CalibreWireless.calibre_messagequeue)
    assert.spy(UIManager.removeZMQ).was_called_with(UIManager, "mock_zmq")
  end)

  it("disconnects active wireless connection from the main menu callback", function()
    local plugin = Calibre:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    local menu_items = {}
    plugin:addToMainMenu(menu_items)

    menu_items.calibre.sub_item_table[1].callback()

    assert.spy(mock_socket.stop).was_called(1)
    assert.is_nil(CalibreWireless.calibre_socket)
    assert.is_nil(CalibreWireless.calibre_messagequeue)
    assert.spy(UIManager.removeZMQ).was_called_with(UIManager, "mock_zmq")
  end)
end)
