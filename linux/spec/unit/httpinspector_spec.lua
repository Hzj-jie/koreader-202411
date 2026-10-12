-- luacheck: ignore 143 231
describe("HttpInspector plugin tests", function()
  local Device, UIManager, NetworkMgr, DataStorage, FileManager
  local HttpInspectorWidget, HttpInspector

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  local function getHttpInspector(widget)
    local i = 1
    while true do
      local name, val = debug.getupvalue(widget.onEnterStandby, i)
      if not name then
        break
      end
      if name == "HttpInspector" then
        return val
      end
      i = i + 1
    end
  end

  before_each(function()
    Device = require("device")
    UIManager = require("ui/uimanager")
    NetworkMgr = require("ui/network/manager")
    DataStorage = require("datastorage")
    FileManager = require("apps/filemanager/filemanager")
    require("ui/widget/filechooser")

    local Dispatcher = require("dispatcher")
    local settings
    local n = 1
    while true do
      local name, value = debug.getupvalue(Dispatcher.init, n)
      if not name then
        break
      end
      if name == "settingsList" then
        settings = value
        break
      end
      n = n + 1
    end
    if settings then
      for _, action in pairs(settings) do
        if type(action) == "table" then
          if
            action.category == "string"
            and not action.args
            and not action.args_func
          then
            action.args = { "opt1" }
            action.toggle = { "Option 1" }
          elseif
            action.category == "absolutenumber"
            or action.category == "incrementalnumber"
          then
            if not action.min then
              action.min = 1
            end
            if not action.max then
              action.max = 100
            end
          elseif
            action.category == "configurable" and not action.configurable
          then
            action.configurable = { name = "cfg", values = { "val1" } }
            action.toggle = { "Option 1" }
          end
        end
      end
    end

    stub(Device, "isKindle")
    Device.isKindle.returns(false)
    stub(Device, "isEmulator")
    Device.isEmulator.returns(false)

    stub(UIManager, "nextTick")
    stub(UIManager, "show")
    stub(UIManager, "close")
    stub(UIManager, "insertZMQ")
    stub(UIManager, "removeZMQ")
    stub(UIManager, "userInput")
    stub(UIManager, "broadcastEvent")
    stub(UIManager, "updateLastUserActionTime")

    stub(NetworkMgr, "isOnline")
    NetworkMgr.isOnline.returns(true)
    stub(NetworkMgr, "ipAddress")
    NetworkMgr.ipAddress.returns("192.168.1.100")

    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderZooming = require("apps/reader/modules/readerzooming")
    local fontlist = require("fontlist")

    stub(FileManager, "getDisplayModeActions").returns(
      { "classic" },
      { "Classic" }
    )
    stub(FileManager, "getSortByActions").returns({ "name" }, { "Name" })
    stub(ReaderHighlight, "getHighlightActions").returns(
      { "highlight" },
      { "Highlight" }
    )
    stub(ReaderZooming, "getZoomModeActions").returns({ "page" }, { "Page" })
    stub(fontlist, "getFontArgFunc").returns({ "font1" }, { "Font1" })

    stub(os, "execute")
    stub(os, "remove")

    G_reader_settings:delete("httpinspector_port")
    G_reader_settings:delete("httpinspector_autostart")

    HttpInspectorWidget = dofile("plugins/httpinspector.koplugin/main.lua")
    HttpInspector = getHttpInspector(HttpInspectorWidget)
    assert.is_not_nil(HttpInspector, "HttpInspector upvalue should not be nil")

    local mock_ui = {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
    }
    FileManager.instance = mock_ui
    HttpInspectorWidget.ui = mock_ui
    HttpInspectorWidget:init()
  end)

  after_each(function()
    FileManager.instance = nil
    Device.isKindle:revert()
    Device.isEmulator:revert()
    UIManager.nextTick:revert()
    UIManager.show:revert()
    UIManager.close:revert()
    UIManager.insertZMQ:revert()
    UIManager.removeZMQ:revert()
    UIManager.userInput:revert()
    UIManager.broadcastEvent:revert()
    UIManager.updateLastUserActionTime:revert()
    NetworkMgr.isOnline:revert()
    NetworkMgr.ipAddress:revert()
    FileManager.getDisplayModeActions:revert()
    FileManager.getSortByActions:revert()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local ReaderZooming = require("apps/reader/modules/readerzooming")
    local fontlist = require("fontlist")
    ReaderHighlight.getHighlightActions:revert()
    ReaderZooming.getZoomModeActions:revert()
    fontlist.getFontArgFunc:revert()
    os.execute:revert()
    os.remove:revert()

    G_reader_settings:delete("httpinspector_port")
    G_reader_settings:delete("httpinspector_autostart")

    if HttpInspector and HttpInspector:isRunning() then
      HttpInspector:stop()
    end

    package.unload("plugins/httpinspector.koplugin/main")
  end)

  it("initializes with default port and registers to main menu", function()
    assert.are.equal(80, HttpInspector.port)

    local menu_items = {}
    HttpInspectorWidget:addToMainMenu(menu_items)
    assert.is_table(menu_items.httpremote)
    assert.is_function(menu_items.httpremote.help_text_func)
    assert.are.equal(3, #menu_items.httpremote.sub_item_table)
  end)

  it("uses emulator port 8080 when running in emulator", function()
    Device.isEmulator.returns(true)
    package.unload("plugins/httpinspector.koplugin/main")

    HttpInspectorWidget = dofile("plugins/httpinspector.koplugin/main.lua")
    HttpInspector = getHttpInspector(HttpInspectorWidget)

    assert.are.equal(8080, HttpInspector.port)
  end)

  it("reads custom port from G_reader_settings", function()
    G_reader_settings:save("httpinspector_port", 9090)
    package.unload("plugins/httpinspector.koplugin/main")

    HttpInspectorWidget = dofile("plugins/httpinspector.koplugin/main.lua")
    HttpInspector = getHttpInspector(HttpInspectorWidget)

    assert.are.equal(9090, HttpInspector.port)
  end)

  it("triggers autostart if httpinspector_autostart is true", function()
    G_reader_settings:save("httpinspector_autostart", true)
    package.unload("plugins/httpinspector.koplugin/main")

    HttpInspectorWidget = dofile("plugins/httpinspector.koplugin/main.lua")
    HttpInspector = getHttpInspector(HttpInspectorWidget)
    HttpInspectorWidget.ui = { menu = { registerToMainMenu = function() end } }
    HttpInspector:init()

    assert.stub(UIManager.nextTick).was_called()
  end)

  it("starts and stops the server correctly", function()
    local mock_socket = {
      port = 8080,
      start = spy.new(function() end),
      stop = spy.new(function() end),
      send = spy.new(function() end),
    }

    local ServerClass = require("ui/message/simpletcpserver")
    stub(ServerClass, "new").returns(mock_socket)

    HttpInspector:start()

    assert.is_true(HttpInspector:isRunning())
    assert.are.equal(8080, HttpInspector.port)
    assert.spy(mock_socket.start).was_called()

    HttpInspector:stop()

    assert.is_false(HttpInspector:isRunning())
    assert.spy(mock_socket.stop).was_called()

    ServerClass.new:revert()
  end)

  it("executes iptables commands on Kindle", function()
    Device.isKindle.returns(true)

    local mock_socket = {
      port = 80,
      start = function() end,
      stop = function() end,
    }
    local ServerClass = require("ui/message/simpletcpserver")
    stub(ServerClass, "new").returns(mock_socket)

    HttpInspector:start()
    assert.stub(os.execute).was_called()

    os.execute:clear()
    HttpInspector:stop()
    assert.stub(os.execute).was_called()

    ServerClass.new:revert()
  end)

  describe("HTTP Response & Request Processing", function()
    local sent_data, sent_id, mock_socket

    before_each(function()
      sent_data = nil
      sent_id = nil
      mock_socket = {
        port = 8080,
        start = function() end,
        stop = function() end,
        send = function(self, data, id)
          sent_data = data
          sent_id = id
        end,
      }
      HttpInspector.http_socket = mock_socket
    end)

    after_each(function()
      HttpInspector.http_socket = nil
    end)

    it("sends response formatted with headers and status code", function()
      local reqinfo = { request_id = 42 }
      HttpInspector:_sendResponse(reqinfo, 200, "text/plain", "Hello World")

      assert.are.equal(42, sent_id)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(
        sent_data:find("Content%-Type: text/plain; charset=utf%-8")
      )
      assert.is_not_nil(sent_data:find("Content%-Length: 11"))
      assert.is_not_nil(sent_data:find("Hello World"))
    end)

    it("sends 302 redirect for location responses", function()
      local reqinfo = { request_id = 1 }
      HttpInspector:_sendResponse(reqinfo, 302, nil, "/koreader/")

      assert.is_not_nil(sent_data:find("HTTP/1.0 302 Found"))
      assert.is_not_nil(sent_data:find("Location: /koreader/"))
    end)

    it("rejects non-GET HTTP requests with 405 Method Not Allowed", function()
      HttpInspector:_processRequest("POST /koreader/ HTTP/1.1\r\n\r\n", 10)
      assert.is_not_nil(sent_data:find("HTTP/1.0 405 Method Not Allowed"))
      assert.is_not_nil(sent_data:find("Only GET supported"))
    end)

    it(
      "redirects root GET request / to /koreader/ when index.html missing",
      function()
        local orig_open = io.open
        stub(io, "open").invokes(function(filepath, mode)
          if filepath == "web/index.html" then
            return nil
          end
          return orig_open(filepath, mode)
        end)

        HttpInspector:_processRequest("GET / HTTP/1.1\r\n\r\n", 11)
        assert.is_not_nil(sent_data:find("HTTP/1.0 302 Found"))
        assert.is_not_nil(sent_data:find("Location: /koreader/"))

        io.open:revert()
      end
    )

    it("returns 404 for missing static files", function()
      HttpInspector:_processRequest("GET /nonexistent.txt HTTP/1.1\r\n\r\n", 12)
      assert.is_not_nil(sent_data:find("HTTP/1.0 404 Not Found"))
      assert.is_not_nil(sent_data:find("Static file not found"))
    end)

    it("returns 200 HTML home page for /koreader/", function()
      HttpInspector:_processRequest("GET /koreader/ HTTP/1.1\r\n\r\n", 13)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("Welcome to KOReader inspector"))
    end)

    it("returns 404 for unknown entry point under /koreader/", function()
      HttpInspector:_processRequest(
        "GET /koreader/unknown_entry/ HTTP/1.1\r\n\r\n",
        14
      )
      assert.is_not_nil(sent_data:find("HTTP/1.0 404 Not Found"))
      assert.is_not_nil(sent_data:find("Unknown entry point."))
    end)
  end)

  describe("Object & Function Exposing", function()
    local sent_data, mock_socket

    before_each(function()
      sent_data = nil
      mock_socket = {
        send = function(self, data)
          sent_data = data
        end,
      }
      HttpInspector.http_socket = mock_socket
    end)

    after_each(function()
      HttpInspector.http_socket = nil
    end)

    it("exposes tables as HTML or JSON", function()
      local test_obj = { num = 42, str = "test", fn = function() end }
      local reqinfo =
        { request_id = 1, parsed_uri = "/test", uri = "/test/", fragments = {} }

      -- Trailing slash: browseObject HTML
      HttpInspector:exposeObject(test_obj, "/", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("text/html"))
      assert.is_not_nil(sent_data:find("num"))

      -- No trailing slash: JSON
      HttpInspector:exposeObject(test_obj, "", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("application/json"))
      assert.is_not_nil(sent_data:find('"num":42'))
    end)

    it("navigates into nested table keys and handles missing keys", function()
      local test_obj = { child = { value = "inner" } }
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/test",
        uri = "/test/child/value",
        fragments = {},
      }

      HttpInspector:exposeObject(test_obj, "/child/value", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("inner"))

      reqinfo = {
        request_id = 1,
        parsed_uri = "/test",
        uri = "/test/missing_key/",
        fragments = {},
      }
      HttpInspector:exposeObject(test_obj, "/missing_key/", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 404 Not Found"))
      assert.is_not_nil(sent_data:find("No such table/object key"))
    end)

    it("handles property assignment via = and ?=", function()
      local test_obj = { count = 10 }

      -- TEXT assignment =
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/test",
        uri = "/test/count=20",
        fragments = { "count", "test_obj" },
      }
      HttpInspector:exposeObject(test_obj, "/count=20", reqinfo)
      assert.are.equal(20, test_obj.count)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(
        sent_data:find("Variable '/test/count' assigned with: 20")
      )

      -- HTML assignment ?=
      reqinfo = {
        request_id = 1,
        parsed_uri = "/test",
        uri = "/test/count?=30",
        fragments = { "count", "test_obj" },
      }
      HttpInspector:exposeObject(test_obj, "/count?=30", reqinfo)
      assert.are.equal(30, test_obj.count)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("text/html"))
    end)

    it("shows function details on ?", function()
      local sample_fn = function(a, b)
        return a + b
      end
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/test/fn",
        uri = "/test/fn?",
        fragments = { "fn" },
      }

      HttpInspector:exposeObject(sample_fn, "?", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("text/html"))
      assert.is_not_nil(
        sent_data:find("accepting or requiring up to 2 arguments")
      )
    end)

    it("calls function and returns JSON or HTML results", function()
      local add_fn = function(a, b)
        return a + b
      end
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/add",
        uri = "/add/5/10",
        fragments = { "add" },
      }

      -- Call as JSON
      HttpInspector:callFunction(add_fn, nil, "5/10", false, reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("%[15%]"))

      -- Call as HTML
      reqinfo = {
        request_id = 1,
        parsed_uri = "/add",
        uri = "/add/5/10",
        fragments = { "add" },
      }
      HttpInspector:callFunction(add_fn, nil, "5/10", true, reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("Success"))
      assert.is_not_nil(sent_data:find("%[15%]"))
    end)

    it("handles function execution errors with 500 status code", function()
      local err_fn = function()
        error("something went wrong")
      end
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/err",
        uri = "/err/",
        fragments = { "err" },
      }

      HttpInspector:callFunction(err_fn, nil, "", false, reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 500 Internal Server Error"))
      assert.is_not_nil(sent_data:find("something went wrong"))
    end)

    it("handles BlitBuffer rendering as PNG", function()
      local ffi = require("ffi")
      pcall(
        ffi.cdef,
        "typedef struct { int dummy_field; } mock_bb_httpinspector_t;"
      )
      local mock_cdata = ffi.new("mock_bb_httpinspector_t")
      local mt = {
        __index = {
          writePNG = function(self, filepath)
            local f = io.open(filepath, "wb")
            if f then
              f:write("PNG_DATA")
              f:close()
            end
          end,
        },
      }
      pcall(ffi.metatype, "mock_bb_httpinspector_t", mt)

      local reqinfo =
        { request_id = 1, parsed_uri = "/bb", uri = "/bb", fragments = {} }

      HttpInspector:exposeObject(mock_cdata, "", reqinfo)
      assert.is_not_nil(sent_data)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("image/png"))
      assert.is_not_nil(sent_data:find("PNG_DATA"))
    end)

    it("rejects non-serializable cdata/userdata with 403", function()
      local dummy_thread = coroutine.create(function() end)
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/thread",
        uri = "/thread",
        fragments = {},
      }

      HttpInspector:exposeObject(dummy_thread, "", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 403 Forbidden"))
      assert.is_not_nil(sent_data:find("Can't act on object of type: thread"))
    end)
  end)

  describe("Event & Input Injection", function()
    local sent_data, mock_socket

    before_each(function()
      sent_data = nil
      mock_socket = {
        send = function(self, data)
          sent_data = data
        end,
      }
      HttpInspector.http_socket = mock_socket
    end)

    after_each(function()
      HttpInspector.http_socket = nil
    end)

    it("exposes dispatcher actions list when no event provided", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/event",
        uri = "/koreader/event",
        fragments = { "event" },
      }
      HttpInspector:exposeEvent("", reqinfo)
      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK", 1, true))
      assert.is_not_nil(
        sent_data:find("List of high-level KOReader events", 1, true)
      )
    end)

    it("schedules event sending when event and args are provided", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/event",
        uri = "/koreader/event/Close",
        fragments = { "event" },
      }
      HttpInspector:exposeEvent("/Close", reqinfo)

      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("Event sent: Close"))
      assert.stub(UIManager.nextTick).was_called()

      -- Invoke nextTick callback to verify UIManager:userInput call
      local tick_fn = UIManager.nextTick.calls[1].refs[2]
      tick_fn()
      assert.stub(UIManager.userInput).was_called()
    end)

    it("handles multiple chained events separated by &", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/event",
        uri = "/koreader/event/Goto/5/&/Close",
        fragments = { "event" },
      }
      HttpInspector:exposeEvent("/Goto/5/&/Close", reqinfo)

      assert.is_not_nil(sent_data:find("Event sent: Goto, Close"))

      local tick_fn = UIManager.nextTick.calls[1].refs[2]
      tick_fn()
      assert.are.equal(2, #UIManager.userInput.calls)
    end)

    it(
      "schedules broadcast event when exposeBroadcastEvent is called",
      function()
        local reqinfo = {
          request_id = 1,
          parsed_uri = "/koreader/broadcast",
          uri = "/koreader/broadcast",
          fragments = { "broadcast" },
        }

        -- Without event: HTML instructions
        HttpInspector:exposeBroadcastEvent("", reqinfo)
        assert.is_not_nil(sent_data:find("Broadcast event"))

        -- With event: schedule broadcast
        reqinfo = {
          request_id = 1,
          parsed_uri = "/koreader/broadcast",
          uri = "/koreader/broadcast/Bookmark",
          fragments = { "broadcast" },
        }
        HttpInspector:exposeBroadcastEvent("/Bookmark", reqinfo)
        assert.is_not_nil(sent_data:find("Event broadcasted: Bookmark"))

        local tick_fn = UIManager.nextTick.calls[1].refs[2]
        tick_fn()
        assert.stub(UIManager.broadcastEvent).was_called()
      end
    )

    it("injects touch gesture when coordinates are valid", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/touch",
        uri = "/koreader/touch/100/200",
        fragments = {},
      }
      HttpInspector:exposeTouch("/100/200", reqinfo)

      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("Touch injected successfully"))
      assert.stub(UIManager.nextTick).was_called()

      local tick_fn = UIManager.nextTick.calls[1].refs[2]
      tick_fn()
      assert.stub(UIManager.userInput).was_called()
    end)

    it("returns error 500 when exposeTouch has invalid coordinates", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/touch",
        uri = "/koreader/touch/100",
        fragments = {},
      }
      HttpInspector:exposeTouch("/100", reqinfo)

      assert.is_not_nil(sent_data:find("HTTP/1.0 500 Internal Server Error"))
      assert.is_not_nil(sent_data:find("Touch requires X and Y coordinates"))
    end)

    it("injects key press and release events when key code is valid", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/key",
        uri = "/koreader/key/Esc",
        fragments = {},
      }
      HttpInspector:exposeKey("/Esc", reqinfo)

      assert.is_not_nil(sent_data:find("HTTP/1.0 200 OK"))
      assert.is_not_nil(sent_data:find("Key injected: Back"))
      assert.stub(UIManager.nextTick).was_called()

      local tick_fn = UIManager.nextTick.calls[1].refs[2]
      tick_fn()
      -- Press and Release events sent
      assert.are.equal(2, #UIManager.userInput.calls)
    end)

    it("returns error 500 when exposeKey is missing keycode", function()
      local reqinfo = {
        request_id = 1,
        parsed_uri = "/koreader/key",
        uri = "/koreader/key",
        fragments = {},
      }
      HttpInspector:exposeKey("", reqinfo)

      assert.is_not_nil(sent_data:find("HTTP/1.0 500 Internal Server Error"))
      assert.is_not_nil(sent_data:find("Key requires a keycode/string"))
    end)
  end)

  describe("Lifecycle Handlers & Main Menu Options", function()
    it("handles lifecycle events: standby, suspend, exit, resume", function()
      local mock_socket = {
        port = 8080,
        start = spy.new(function() end),
        stop = spy.new(function() end),
      }
      local ServerClass = require("ui/message/simpletcpserver")
      stub(ServerClass, "new").returns(mock_socket)

      HttpInspector:start()
      assert.is_true(HttpInspector:isRunning())

      HttpInspectorWidget:onEnterStandby()
      assert.is_false(HttpInspector:isRunning())

      HttpInspector:start()
      HttpInspectorWidget:onSuspend()
      assert.is_false(HttpInspector:isRunning())

      HttpInspector:start()
      HttpInspectorWidget:onExit()
      assert.is_false(HttpInspector:isRunning())

      HttpInspectorWidget:onLeaveStandby()
      HttpInspectorWidget:onResume()

      ServerClass.new:revert()
    end)

    it("tests main menu help text and callbacks", function()
      local menu_items = {}
      HttpInspectorWidget:addToMainMenu(menu_items)

      local httpremote = menu_items.httpremote
      assert.is_string(httpremote.help_text_func())

      -- Offline mode help text
      NetworkMgr.isOnline.returns(false)
      assert.is_string(httpremote.help_text_func())

      -- Sub item 1: Start/stop toggle
      local sub1 = httpremote.sub_item_table[1]
      assert.is_string(sub1.text_func())
      local mock_menu = { updateItems = spy.new(function() end) }
      sub1.callback(mock_menu) -- toggles start
      assert.spy(mock_menu.updateItems).was_called()

      -- Sub item 2: Auto start toggle
      local sub2 = httpremote.sub_item_table[2]
      assert.is_boolean(sub2.checked_func())
      sub2.callback()
      assert.is_true(G_reader_settings:isTrue("httpinspector_autostart"))

      -- Sub item 3: Port dialog
      local sub3 = httpremote.sub_item_table[3]
      assert.is_string(sub3.text_func())
      sub3.callback(mock_menu)
      assert.stub(UIManager.show).was_called()
    end)
  end)
end)
