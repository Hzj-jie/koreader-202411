describe("Calibre Wireless module", function()
  local CalibreWireless, CalibreMetadata, CalibreSearch, UIManager, NetworkMgr, G_reader_settings
  local util, FFIUtil, rapidjson, sha, socket, lfs, FileManager, InputDialog

  local test_dir = "/tmp/calibre_wireless_test_" .. os.time()

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    CalibreWireless = require("plugins/calibre.koplugin/wireless")
    CalibreMetadata = require("plugins/calibre.koplugin/metadata")
    CalibreSearch = require("plugins/calibre.koplugin/search")
    UIManager = require("ui/uimanager")
    NetworkMgr = require("ui/network/manager")
    util = require("util")
    FFIUtil = require("ffi/util")
    rapidjson = require("rapidjson")
    sha = require("ffi/sha2")
    socket = require("socket")
    lfs = require("libs/libkoreader-lfs")
    FileManager = require("apps/filemanager/filemanager")
    InputDialog = require("ui/widget/inputdialog")
  end)

  local wireless_inst

  before_each(function()
    local settings_store = {}
    G_reader_settings = {
      read = function(_, key)
        return settings_store[key]
      end,
      save = function(_, key, val)
        settings_store[key] = val
      end,
      delete = function(_, key)
        settings_store[key] = nil
      end,
      has = function(_, key)
        return settings_store[key] ~= nil
      end,
      hasNot = function(_, key)
        return settings_store[key] == nil
      end,
      isTrue = function(_, key)
        return settings_store[key] == true
      end,
      isFalse = function(_, key)
        return settings_store[key] == false
      end,
      nilOrTrue = function(_, key)
        local val = settings_store[key]
        return val == nil or val == true
      end,
      nilOrFalse = function(_, key)
        return settings_store[key] == false
      end,
      readTableRef = function(_, key)
        return settings_store[key] or {}
      end,
      flush = function() end,
    }
    _G.G_reader_settings = G_reader_settings

    wireless_inst = CalibreWireless:new()
    wireless_inst:init()

    stub(FileManager, "getCurrentDir").returns(nil)

    lfs.mkdir(test_dir)
    G_reader_settings:save("inbox_dir", test_dir)
  end)

  after_each(function()
    if wireless_inst then
      wireless_inst:_disconnect()
    end

    if FileManager.getCurrentDir.revert then
      FileManager.getCurrentDir:revert()
    end

    -- Clean up test files in test_dir
    local function rmdir_recursive(path)
      local mode = lfs.attributes(path, "mode")
      if mode == "directory" then
        for file in lfs.dir(path) do
          if file ~= "." and file ~= ".." then
            rmdir_recursive(path .. "/" .. file)
          end
        end
        lfs.rmdir(path)
      elseif mode == "file" then
        os.remove(path)
      end
    end
    rmdir_recursive(test_dir)
  end)

  describe("Module initialization", function()
    it("should initialize default properties and opcode names", function()
      assert.is_table(wireless_inst)
      assert.are.same(wireless_inst.id, "KOReader")
      assert.are.same(wireless_inst.port, 8134)
      assert.is_table(wireless_inst.opcodes)
      assert.is_table(wireless_inst.opnames)

      -- Check opcode mapping bidirectionality
      assert.are.same(wireless_inst.opnames[0], "OK")
      assert.are.same(wireless_inst.opnames[9], "GET_INITIALIZATION_INFO")
      assert.are.same(wireless_inst.opnames[12], "NOOP")
      assert.are.same(wireless_inst.opnames[8], "SEND_BOOK")
      assert.are.same(wireless_inst.opnames[13], "DELETE_BOOK")
    end)

    it(
      "should correctly compare Calibre versions in isCalibreAtLeast",
      function()
        wireless_inst.calibre.version = { 4, 18, 0 }

        assert.is_true(wireless_inst:isCalibreAtLeast(4, 18, 0))
        assert.is_true(wireless_inst:isCalibreAtLeast(4, 17, 99))
        assert.is_true(wireless_inst:isCalibreAtLeast(3, 20, 0))
        assert.is_false(wireless_inst:isCalibreAtLeast(4, 18, 1))
        assert.is_false(wireless_inst:isCalibreAtLeast(5, 0, 0))
      end
    )
  end)

  describe("Network and Server Discovery", function()
    it("should discover calibre server via UDP broadcast", function()
      local mock_udp = {
        setoption = function() end,
        setsockname = function() end,
        settimeout = function() end,
        sendto = function()
          return true
        end,
        receivefrom = function()
          return "calibre wireless device client (on test_host);8080,9090",
            "192.168.1.50"
        end,
      }

      stub(socket, "udp4").returns(mock_udp)

      local host, port = wireless_inst:find_calibre_server()
      assert.are.same(host, "192.168.1.50")
      assert.are.same(port, "9090")

      socket.udp4:revert()
    end)

    it("should return nil if UDP broadcast fails to discover server", function()
      local mock_udp = {
        setoption = function() end,
        setsockname = function() end,
        settimeout = function() end,
        sendto = function()
          return nil, "connection failed"
        end,
      }

      stub(socket, "udp4").returns(mock_udp)

      local host, port = wireless_inst:find_calibre_server()
      assert.is_nil(host)
      assert.is_nil(port)

      socket.udp4:revert()
    end)

    it("should check calibre server TCP connection availability", function()
      local mock_tcp_success = {
        settimeout = function() end,
        connect = function()
          return 1
        end,
        close = function() end,
      }

      stub(socket, "tcp").returns(mock_tcp_success)
      local ok = wireless_inst:checkCalibreServer("127.0.0.1", 9090)
      assert.is_true(ok)
      socket.tcp:revert()

      local mock_tcp_fail = {
        settimeout = function() end,
        connect = function()
          return nil, "connection refused"
        end,
      }

      stub(socket, "tcp").returns(mock_tcp_fail)
      local ok_fail, err = wireless_inst:checkCalibreServer("127.0.0.1", 9090)
      assert.is_false(ok_fail)
      assert.are.same(err, "connection refused")
      socket.tcp:revert()
    end)

    it("should initiate connection when network is connected", function()
      stub(NetworkMgr, "runWhenConnected", function(_, cb)
        cb()
      end)

      stub(wireless_inst, "find_calibre_server").returns("192.168.1.100", 8134)
      stub(wireless_inst, "checkCalibreServer").returns(true)
      stub(CalibreMetadata, "init")
      stub(wireless_inst, "initCalibreMQ")

      wireless_inst:connect()

      assert.spy(wireless_inst.find_calibre_server).was_called(1)
      assert
        .spy(wireless_inst.checkCalibreServer)
        .was_called_with(wireless_inst, "192.168.1.100", 8134)
      assert
        .spy(CalibreMetadata.init)
        .was_called_with(CalibreMetadata, test_dir)
      assert
        .spy(wireless_inst.initCalibreMQ)
        .was_called_with(wireless_inst, "192.168.1.100", 8134)

      NetworkMgr.runWhenConnected:revert()
      wireless_inst.find_calibre_server:revert()
      wireless_inst.checkCalibreServer:revert()
      CalibreMetadata.init:revert()
      wireless_inst.initCalibreMQ:revert()
    end)

    it(
      "should use specified calibre_wireless_url if configured in settings",
      function()
        G_reader_settings:save(
          "calibre_wireless_url",
          { address = "10.0.0.5", port = 9999 }
        )

        stub(NetworkMgr, "runWhenConnected", function(_, cb)
          cb()
        end)

        stub(wireless_inst, "checkCalibreServer").returns(true)
        stub(CalibreMetadata, "init")
        stub(wireless_inst, "initCalibreMQ")

        wireless_inst:connect()

        assert
          .spy(wireless_inst.checkCalibreServer)
          .was_called_with(wireless_inst, "10.0.0.5", 9999)
        assert
          .spy(wireless_inst.initCalibreMQ)
          .was_called_with(wireless_inst, "10.0.0.5", 9999)

        NetworkMgr.runWhenConnected:revert()
        wireless_inst.checkCalibreServer:revert()
        CalibreMetadata.init:revert()
        wireless_inst.initCalibreMQ:revert()
      end
    )

    it(
      "should show error message when connection check fails in connect",
      function()
        stub(NetworkMgr, "runWhenConnected", function(_, cb)
          cb()
        end)

        stub(wireless_inst, "find_calibre_server").returns(
          "192.168.1.100",
          8134
        )
        stub(wireless_inst, "checkCalibreServer").returns(false, "Timeout")
        stub(UIManager, "show")

        wireless_inst:connect()

        assert.spy(UIManager.show).was_called()

        NetworkMgr.runWhenConnected:revert()
        wireless_inst.find_calibre_server:revert()
        wireless_inst.checkCalibreServer:revert()
        UIManager.show:revert()
      end
    )
  end)

  describe("Disconnection and lifecycle", function()
    it(
      "should clean up socket, message queue, metadata, and search cache on disconnect",
      function()
        local mock_socket = {
          stop = spy.new(function() end),
        }
        wireless_inst.calibre_socket = mock_socket
        wireless_inst.calibre_messagequeue = "mock_zmq_handle"

        stub(UIManager, "removeZMQ")
        stub(CalibreMetadata, "clean")
        stub(CalibreSearch, "invalidateCache")

        wireless_inst:_disconnect()

        assert.spy(mock_socket.stop).was_called(1)
        assert.is_nil(wireless_inst.calibre_socket)
        assert
          .spy(UIManager.removeZMQ)
          .was_called_with(UIManager, "mock_zmq_handle")
        assert.is_nil(wireless_inst.calibre_messagequeue)
        assert.spy(CalibreMetadata.clean).was_called(1)
        assert.spy(CalibreSearch.invalidateCache).was_called(1)

        UIManager.removeZMQ:revert()
        CalibreMetadata.clean:revert()
        CalibreSearch.invalidateCache:revert()
      end
    )

    it("should call disconnect onExit and onClose", function()
      stub(wireless_inst, "_disconnect")

      wireless_inst:onExit()
      assert.spy(wireless_inst._disconnect).was_called(1)

      wireless_inst:onClose()
      assert.spy(wireless_inst._disconnect).was_called(2)

      wireless_inst._disconnect:revert()
    end)

    it("should sleep and reconnect in reconnect", function()
      stub(FFIUtil, "sleep")
      stub(wireless_inst, "_disconnect")
      stub(wireless_inst, "connect")

      wireless_inst:reconnect()

      assert.spy(FFIUtil.sleep).was_called(2)
      assert.spy(wireless_inst._disconnect).was_called(1)
      assert.spy(wireless_inst.connect).was_called(1)

      FFIUtil.sleep:revert()
      wireless_inst._disconnect:revert()
      wireless_inst.connect:revert()
    end)
  end)

  describe("JSON Encoding & Stream Receiver", function()
    it("should encode and send JSON packet with length prefix", function()
      local sent_data = nil
      wireless_inst.calibre_socket = {
        send = function(_, data)
          sent_data = data
        end,
        stop = function() end,
      }

      wireless_inst:sendJsonData("OK", { test = 123 })

      assert.is_not_nil(sent_data)
      -- Formatted as: <len>[0, {"test":123}]
      local len_str, json_str = sent_data:match("^(%d+)(%[.*%])$")
      assert.is_not_nil(len_str)
      assert.are.same(tonumber(len_str), #json_str)

      local decoded = rapidjson.decode(json_str)
      assert.are.same(decoded[1], 0) -- OK opcode
      assert.are.same(decoded[2].test, 123)
    end)

    it(
      "should parse incoming length-prefixed JSON buffers in onReceiveJSON",
      function()
        stub(wireless_inst, "getInitInfo")
        stub(wireless_inst, "getDeviceInfo")

        local payload1 =
          rapidjson.encode({ 9, { calibre_version = { 5, 0, 0 } } })
        local payload2 = rapidjson.encode({ 3, {} })

        local stream = tostring(#payload1)
          .. payload1
          .. tostring(#payload2)
          .. payload2

        wireless_inst:onReceiveJSON(stream)

        assert.spy(wireless_inst.getInitInfo).was_called(1)
        assert.spy(wireless_inst.getDeviceInfo).was_called(1)

        wireless_inst.getInitInfo:revert()
        wireless_inst.getDeviceInfo:revert()
      end
    )

    it(
      "should buffer incomplete JSON chunks until full payload arrives",
      function()
        stub(wireless_inst, "noop")

        local payload = rapidjson.encode({ 12, { test = true } })
        local full = tostring(#payload) .. payload

        -- Send first half
        wireless_inst:onReceiveJSON(full:sub(1, 5))
        assert.spy(wireless_inst.noop).was_called(0)
        assert.are.same(wireless_inst.buffer, full:sub(1, 5))

        -- Send remaining half
        wireless_inst:onReceiveJSON(full:sub(6))
        assert.spy(wireless_inst.noop).was_called(1)
        assert.are.same(wireless_inst.buffer, "")

        wireless_inst.noop:revert()
      end
    )

    it(
      "should execute JSONReceiveCallback and schedule password check message",
      function()
        stub(UIManager, "scheduleIn")
        wireless_inst.calibre_socket =
          { host = "127.0.0.1", port = 8134, stop = function() end }
        stub(wireless_inst, "onReceiveJSON")

        local callback = wireless_inst:JSONReceiveCallback("127.0.0.1", 8134)
        assert.is_function(callback)

        callback({ "test_data" })

        assert.spy(wireless_inst.onReceiveJSON).was_called(1)
        assert.is_true(wireless_inst.connect_message)
        assert
          .spy(UIManager.scheduleIn)
          .was_called_with(UIManager, 1, wireless_inst.password_check_callback)

        UIManager.scheduleIn:revert()
        wireless_inst.onReceiveJSON:revert()
      end
    )
  end)

  describe("Opcode Handlers", function()
    before_each(function()
      wireless_inst.calibre_socket = {
        send = spy.new(function() end),
        stop = spy.new(function() end),
      }
    end)

    it("should respond to GET_INITIALIZATION_INFO (getInitInfo)", function()
      G_reader_settings:save("calibre_wireless_password", "secret")

      local arg = {
        calibre_version = { 5, 12, 0 },
        passwordChallenge = "challenge123",
      }

      wireless_inst:getInitInfo(arg)

      assert.are.same(wireless_inst.calibre.version, { 5, 12, 0 })
      assert.are.same(wireless_inst.calibre.version_string, "5.12.0")
      assert.spy(wireless_inst.calibre_socket.send).was_called(1)

      -- Verify password challenge hash matches sha1("secretchallenge123")
      local expected_hash = sha.sha1("secretchallenge123")
      local sent_arg = wireless_inst.calibre_socket.send.calls[1].vals[2]
      local _, json_body = sent_arg:match("^(%d+)(%[.*%])$")
      local decoded = rapidjson.decode(json_body)
      assert.are.same(decoded[2].passwordHash, expected_hash)
      assert.are.same(decoded[2].appName, "KOReader")
    end)

    it(
      "should open password dialog and update settings in setPassword",
      function()
        stub(UIManager, "show")
        stub(InputDialog, "new").returns({
          getInputText = function()
            return "newpass"
          end,
        })

        wireless_inst:setPassword()

        assert.spy(UIManager.show).was_called(1)
        assert.spy(InputDialog.new).was_called()

        UIManager.show:revert()
        InputDialog.new:revert()
      end
    )

    it("should respond to GET_DEVICE_INFORMATION (getDeviceInfo)", function()
      CalibreMetadata.drive = { device_store_uuid = "uuid-12345" }

      wireless_inst:getDeviceInfo({})

      assert.spy(wireless_inst.calibre_socket.send).was_called(1)
      local sent_arg = wireless_inst.calibre_socket.send.calls[1].vals[2]
      local _, json_body = sent_arg:match("^(%d+)(%[.*%])$")
      local decoded = rapidjson.decode(json_body)
      assert.are.same(decoded[2].device_info.device_store_uuid, "uuid-12345")
    end)

    it("should handle SET_CALIBRE_DEVICE_INFO (setCalibreInfo)", function()
      stub(CalibreMetadata, "saveDeviceInfo")

      wireless_inst:setCalibreInfo({ info = "test" })

      assert
        .spy(CalibreMetadata.saveDeviceInfo)
        .was_called_with(CalibreMetadata, { info = "test" })
      assert.spy(wireless_inst.calibre_socket.send).was_called(1)

      CalibreMetadata.saveDeviceInfo:revert()
    end)

    it(
      "should respond with available disk space in FREE_SPACE (getFreeSpace)",
      function()
        wireless_inst:getFreeSpace({})

        assert.spy(wireless_inst.calibre_socket.send).was_called(1)
        local sent_arg = wireless_inst.calibre_socket.send.calls[1].vals[2]
        local _, json_body = sent_arg:match("^(%d+)(%[.*%])$")
        local decoded = rapidjson.decode(json_body)
        assert.is_number(decoded[2].free_space_on_device)
      end
    )

    it("should handle SET_LIBRARY_INFO (setLibraryInfo)", function()
      wireless_inst:setLibraryInfo({})
      assert.spy(wireless_inst.calibre_socket.send).was_called(1)
    end)

    it("should respond to GET_BOOK_COUNT (getBookCount)", function()
      CalibreMetadata.books = { { title = "Book 1" }, { title = "Book 2" } }
      stub(CalibreMetadata, "getBookId").returns({ id = 1 })

      wireless_inst:getBookCount({})

      -- Initial count response + 2 individual book ID responses = 3 total sends
      assert.spy(wireless_inst.calibre_socket.send).was_called(3)

      CalibreMetadata.getBookId:revert()
    end)

    it("should handle NOOP opcodes appropriately", function()
      -- Test server eject
      stub(wireless_inst, "_disconnect")
      wireless_inst:noop({ ejecting = true })
      assert.is_true(wireless_inst.disconnected_by_server)
      assert.spy(wireless_inst._disconnect).was_called(1)
      wireless_inst._disconnect:revert()

      -- Test metadata batch count init
      wireless_inst:noop({ count = 5 })
      assert.are.same(wireless_inst.pending, 5)
      assert.are.same(wireless_inst.current, 1)

      -- Test metadata item fetch by priKey
      stub(CalibreMetadata, "getBookMetadata").returns({ title = "Meta" })
      wireless_inst:noop({ priKey = 10 })
      assert
        .spy(CalibreMetadata.getBookMetadata)
        .was_called_with(CalibreMetadata, 10)
      CalibreMetadata.getBookMetadata:revert()

      -- Test default keep-alive NOOP
      wireless_inst:noop({})
      assert.spy(wireless_inst.calibre_socket.send).was_called()
    end)

    it(
      "should update invalid_password status in DISPLAY_MESSAGE (serverFeedback)",
      function()
        wireless_inst:serverFeedback({ messageKind = 1 })
        assert.is_true(wireless_inst.invalid_password)
      end
    )

    it("should stream requested book file segment in sendToCalibre", function()
      local sample_file = test_dir .. "/sample.txt"
      local f = io.open(sample_file, "w")
      if f then
        f:write("Hello KOReader Calibre Wireless")
        f:close()
      end

      wireless_inst:sendToCalibre({ lpath = "sample.txt" })

      -- Should send initial OK response with fileLength + streamed file content
      assert.spy(wireless_inst.calibre_socket.send).was_called()
      local first_send = wireless_inst.calibre_socket.send.calls[1].vals[2]
      local _, json_body = first_send:match("^(%d+)(%[.*%])$")
      local decoded = rapidjson.decode(json_body)
      assert.are.same(decoded[2].fileLength, 31)
    end)

    it(
      "should handle DELETE_BOOK by removing files and updating metadata",
      function()
        local file_to_delete = test_dir .. "/delete_me.txt"
        local f = io.open(file_to_delete, "w")
        if f then
          f:write("dummy")
          f:close()
        end

        CalibreMetadata.books = { { title = "Delete Me" } }
        stub(CalibreMetadata, "getBookUuid").returns("uuid-999", 1)
        stub(CalibreMetadata, "removeBook")
        stub(CalibreMetadata, "saveBookList")
        stub(UIManager, "show")

        wireless_inst:deleteBook({ lpaths = { "delete_me.txt" } })

        assert.is_nil(util.fileExists(file_to_delete))
        assert
          .spy(CalibreMetadata.removeBook)
          .was_called_with(CalibreMetadata, "delete_me.txt")
        assert.spy(CalibreMetadata.saveBookList).was_called(1)
        assert.spy(UIManager.show).was_called()

        CalibreMetadata.getBookUuid:revert()
        CalibreMetadata.removeBook:revert()
        CalibreMetadata.saveBookList:revert()
        UIManager.show:revert()
      end
    )

    it(
      "should receive SEND_BOOK and write file payload in raw binary mode",
      function()
        stub(CalibreMetadata, "addBook")
        stub(CalibreMetadata, "saveBookList")
        stub(UIManager, "show")

        local arg = {
          lpath = "received_book.epub",
          length = 12,
          thisBook = 0,
          totalBooks = 1,
          metadata = { title = "Received Book" },
        }

        wireless_inst:sendBook(arg)

        -- Verify raw receiveCallback was attached to calibre_socket
        assert.is_function(wireless_inst.calibre_socket.receiveCallback)

        -- Simulate socket sending 12 bytes of raw book content
        wireless_inst.calibre_socket.receiveCallback({ "Hello World!" })

        local dest_path = test_dir .. "/received_book.epub"
        assert.is_true(util.fileExists(dest_path))

        local read_f = io.open(dest_path, "r")
        if read_f then
          local content = read_f:read("*all")
          read_f:close()
          assert.are.same(content, "Hello World!")
        end

        assert
          .spy(CalibreMetadata.addBook)
          .was_called_with(CalibreMetadata, arg.metadata)
        assert.spy(CalibreMetadata.saveBookList).was_called(1)

        CalibreMetadata.addBook:revert()
        CalibreMetadata.saveBookList:revert()
        UIManager.show:revert()
      end
    )

    it(
      "should handle SEND_BOOK error when disk space is insufficient for Calibre >= 4.18",
      function()
        wireless_inst.calibre.version = { 4, 18, 0 }

        -- Force getFreeSpace to return 0 bytes
        stub(util, "diskUsage").returns({ available = 0 })

        local arg = {
          lpath = "large_book.epub",
          length = 10 * 1024 * 1024,
          thisBook = 0,
          totalBooks = 1,
        }

        wireless_inst:sendBook(arg)

        assert.spy(wireless_inst.calibre_socket.send).was_called(1)
        local sent_arg = wireless_inst.calibre_socket.send.calls[1].vals[2]
        local _, json_body = sent_arg:match("^(%d+)(%[.*%])$")
        local decoded = rapidjson.decode(json_body)

        assert.are.same(decoded[1], 20) -- ERROR opcode
        assert.is_not_nil(decoded[2].message)

        util.diskUsage:revert()
      end
    )
  end)
end)
