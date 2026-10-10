-- luacheck: ignore 122
describe("Calibre Wireless plugin module", function()
  local CalibreWireless, CalibreMetadata, CalibreSearch, UIManager
  local util, FFIUtil, rapidjson, socket, InputDialog

  setup(function()
    require("commonrequire")
    CalibreWireless = require("plugins/calibre.koplugin/wireless")
    CalibreMetadata = require("plugins/calibre.koplugin/metadata")
    CalibreSearch = require("plugins/calibre.koplugin/search")
    UIManager = require("ui/uimanager")
    util = require("util")
    FFIUtil = require("ffi/util")
    rapidjson = require("rapidjson")
    socket = require("socket")
    InputDialog = require("ui/widget/inputdialog")
  end)

  local wireless_inst

  before_each(function()
    wireless_inst = CalibreWireless:new()
    wireless_inst:init()
  end)

  describe("Lifecycle and protocol handling", function()
    it("initializes opnames dictionary reversing opcodes", function()
      assert.is_table(wireless_inst.opcodes)
      assert.is_table(wireless_inst.opnames)
      assert.are.equal("NOOP", wireless_inst.opnames[12])
      assert.are.equal("OK", wireless_inst.opnames[0])
      assert.are.equal("FREE_SPACE", wireless_inst.opnames[5])
      assert.are.equal("GET_INITIALIZATION_INFO", wireless_inst.opnames[9])
    end)

    it("evaluates isCalibreAtLeast version comparisons", function()
      wireless_inst.calibre = { version = { 4, 18, 0 } }
      assert.is_true(wireless_inst:isCalibreAtLeast(3, 0, 0))
      assert.is_true(wireless_inst:isCalibreAtLeast(4, 17, 0))
      assert.is_true(wireless_inst:isCalibreAtLeast(4, 18, 0))
      assert.is_false(wireless_inst:isCalibreAtLeast(4, 19, 0))
      assert.is_false(wireless_inst:isCalibreAtLeast(5, 0, 0))
    end)

    it("verifies server accessibility with checkCalibreServer", function()
      local orig_tcp = socket.tcp
      local connected = false
      local mock_tcp = {
        settimeout = function() end,
        connect = function(_, host, port)
          if host == "192.168.1.1" and port == 9090 then
            connected = true
            return 1
          end
          return nil, "connection refused"
        end,
        close = function() end,
      }
      socket.tcp = function()
        return mock_tcp
      end
      finally(function()
        socket.tcp = orig_tcp
      end)

      assert.is_true(wireless_inst:checkCalibreServer("192.168.1.1", 9090))
      assert.is_true(connected)
      assert.is_false(wireless_inst:checkCalibreServer("192.168.1.2", 9090))
    end)

    it(
      "disconnects socket and cleans metadata and search caches on _disconnect",
      function()
        local socket_stopped = false
        wireless_inst.calibre_socket = {
          stop = function()
            socket_stopped = true
          end,
        }
        local test_mq = {}
        wireless_inst.calibre_messagequeue = test_mq
        local orig_removeZMQ = UIManager.removeZMQ
        local removed_zmq = nil
        UIManager.removeZMQ = function(_, mq)
          removed_zmq = mq
        end

        local orig_clean = CalibreMetadata.clean
        local metadata_cleaned = false
        CalibreMetadata.clean = function()
          metadata_cleaned = true
        end

        local orig_invalidate = CalibreSearch.invalidateCache
        local cache_invalidated = false
        CalibreSearch.invalidateCache = function()
          cache_invalidated = true
        end

        finally(function()
          UIManager.removeZMQ = orig_removeZMQ
          CalibreMetadata.clean = orig_clean
          CalibreSearch.invalidateCache = orig_invalidate
        end)

        wireless_inst:_disconnect()
        assert.is_true(socket_stopped)
        assert.is_nil(wireless_inst.calibre_socket)
        assert.are.equal(test_mq, removed_zmq)
        assert.is_nil(wireless_inst.calibre_messagequeue)
        assert.is_true(metadata_cleaned)
        assert.is_true(cache_invalidated)
      end
    )

    it("reconnects by calling _disconnect and connect", function()
      local orig_sleep = FFIUtil.sleep
      FFIUtil.sleep = function() end
      local disconnected, connected = false, false
      local orig_disc = wireless_inst._disconnect
      local orig_conn = wireless_inst.connect
      wireless_inst._disconnect = function()
        disconnected = true
      end
      wireless_inst.connect = function()
        connected = true
      end
      finally(function()
        FFIUtil.sleep = orig_sleep
        wireless_inst._disconnect = orig_disc
        wireless_inst.connect = orig_conn
      end)

      wireless_inst:reconnect()
      assert.is_true(disconnected)
      assert.is_true(connected)
    end)

    it(
      "formats and transmits length-prefixed JSON frames in sendJsonData",
      function()
        local sent_raw = nil
        wireless_inst.calibre_socket = {
          send = function(_, payload)
            sent_raw = payload
            return #payload
          end,
        }

        wireless_inst:sendJsonData("OK", { status = "ready" })
        assert.is_string(sent_raw)
        local len_str, body = sent_raw:match("^(%d+)(%[.*%])$")
        assert.is_not_nil(len_str)
        assert.are.equal(#body, tonumber(len_str))

        local decoded = rapidjson.decode(body)
        assert.is_table(decoded)
        assert.are.equal(0, decoded[1]) -- OK opcode
        assert.are.equal("ready", decoded[2].status)
      end
    )

    it(
      "parses incoming stream chunks and handles multiple length-prefixed JSON frames",
      function()
        wireless_inst.calibre_socket = {
          send = function() end,
        }
        local handled_opcodes = {}
        local orig_noop = wireless_inst.noop
        local orig_free = wireless_inst.getFreeSpace
        wireless_inst.noop = function(_, arg)
          table.insert(handled_opcodes, { op = "NOOP", arg = arg })
        end
        wireless_inst.getFreeSpace = function(_, arg)
          table.insert(handled_opcodes, { op = "FREE_SPACE", arg = arg })
        end
        finally(function()
          wireless_inst.noop = orig_noop
          wireless_inst.getFreeSpace = orig_free
        end)

        -- Two frames: NOOP (opcode 12) and FREE_SPACE (opcode 5)
        local frame1 = "[12,{}]"
        local frame2 = '[5,{"type":"storage"}]'
        local msg1 = string.format("%d%s", #frame1, frame1)
        local msg2 = string.format("%d%s", #frame2, frame2)

        -- Feed in two partial pieces: part1 is incomplete (first 4 chars of frame1)
        local full_stream = msg1 .. msg2
        local part1 = full_stream:sub(1, 4)
        local part2 = full_stream:sub(5)

        wireless_inst:onReceiveJSON(part1)
        assert.are.equal(0, #handled_opcodes)

        wireless_inst:onReceiveJSON(part2)
        assert.are.equal(2, #handled_opcodes)
        assert.are.equal("NOOP", handled_opcodes[1].op)
        assert.are.equal("FREE_SPACE", handled_opcodes[2].op)
        assert.are.equal("storage", handled_opcodes[2].arg.type)
      end
    )

    it("handles core protocol opcodes via dedicated handlers", function()
      local sent_messages = {}
      wireless_inst.calibre_socket = {
        send = function() end,
      }
      wireless_inst.sendJsonData = function(_, op, data)
        table.insert(sent_messages, { op = op, data = data })
      end

      -- NOOP
      wireless_inst:noop({})
      assert.are.equal("OK", sent_messages[#sent_messages].op)

      -- GET_DEVICE_INFORMATION
      wireless_inst:getDeviceInfo({})
      assert.are.equal("OK", sent_messages[#sent_messages].op)
      assert.is_table(sent_messages[#sent_messages].data.device_info)
      assert.are.equal(
        wireless_inst.version,
        sent_messages[#sent_messages].data.device_version
      )

      -- SET_CALIBRE_DEVICE_INFO
      local saved_info = nil
      local orig_save = CalibreMetadata.saveDeviceInfo
      CalibreMetadata.saveDeviceInfo = function(_, info)
        saved_info = info
      end

      -- GET_BOOK_COUNT
      local orig_books = CalibreMetadata.books
      local orig_getBookId = CalibreMetadata.getBookId
      CalibreMetadata.books = { { id = 1 }, { id = 2 } }
      CalibreMetadata.getBookId = function(_, idx)
        return { lpath = "book" .. idx .. ".epub" }
      end

      finally(function()
        CalibreMetadata.saveDeviceInfo = orig_save
        CalibreMetadata.books = orig_books
        CalibreMetadata.getBookId = orig_getBookId
      end)

      wireless_inst:setCalibreInfo({ calibre_version = { 5, 0, 0 } })
      assert.are.equal("OK", sent_messages[#sent_messages].op)
      assert.are.same({ 5, 0, 0 }, saved_info.calibre_version)

      -- SET_LIBRARY_INFO
      wireless_inst:setLibraryInfo({
        library_uuid = "lib-uuid-1",
        library_name = "Default",
      })
      assert.are.equal("OK", sent_messages[#sent_messages].op)

      wireless_inst:getBookCount({})
      assert.are.equal("OK", sent_messages[#sent_messages].op)
      assert.are.equal(2, sent_messages[#sent_messages - 2].data.count)
    end)

    it("sets password in G_reader_settings via setPassword dialog", function()
      local orig_new = InputDialog.new
      local captured_dlg = nil
      InputDialog.new = function(self, args)
        local dlg = orig_new(self, args)
        captured_dlg = dlg
        return dlg
      end

      local orig_show = UIManager.show
      local orig_close = UIManager.close
      UIManager.show = function() end
      UIManager.close = function() end

      finally(function()
        InputDialog.new = orig_new
        UIManager.show = orig_show
        UIManager.close = orig_close
        G_reader_settings:delete("calibre_wireless_password")
      end)

      wireless_inst:setPassword()
      assert.is_table(captured_dlg)

      captured_dlg.getInputText = function()
        return "Secret123"
      end

      local submit_btn = captured_dlg.buttons[1][2]
      assert.are.equal("Set password", submit_btn.text)
      submit_btn.callback()

      assert.are.equal(
        "Secret123",
        G_reader_settings:read("calibre_wireless_password")
      )
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes find_calibre_server leaking UDP socket and aborting on non-Calibre datagram",
      function()
        local orig_udp4 = socket.udp4
        local closed = false
        local calls = 0

        local mock_udp = {
          setoption = function() end,
          setsockname = function() end,
          settimeout = function() end,
          sendto = function()
            return 5
          end,
          receivefrom = function()
            calls = calls + 1
            if calls == 1 then
              -- Port 1 replies with an unrelated broadcast packet
              return "unrelated packet", "192.168.1.50"
            else
              -- Port 2 replies with valid Calibre broadcast datagram
              return "calibre wireless device client (on MyPC);8080,9090",
                "192.168.1.100"
            end
          end,
          close = function()
            closed = true
          end,
        }

        socket.udp4 = function()
          return mock_udp
        end
        finally(function()
          socket.udp4 = orig_udp4
        end)

        -- In wireless.lua:100-120:
        -- 1) udp:close() is never called, leaking the bound socket.
        -- 2) lines 111-116: if dgram and host then return host, replied_port end
        -- returns immediately on the first received datagram even when replied_port is nil,
        -- aborting discovery for remaining ports.
        local host, port = wireless_inst:find_calibre_server()
        assert.are.equal("192.168.1.100", host)
        assert.are.equal("9090", port)
        assert.is_true(closed, "UDP socket must be closed via udp:close()")
      end
    )

    it(
      "fails: exposes deleteBook crashing when a book metadata entry has title = nil",
      function()
        local orig_books = CalibreMetadata.books
        local orig_getBookUuid = CalibreMetadata.getBookUuid
        local orig_removeBook = CalibreMetadata.removeBook
        local orig_removeFile = util.removeFile

        G_reader_settings:save("inbox_dir", "/tmp")

        CalibreMetadata.books = {
          [1] = {
            lpath = "book.epub",
            title = nil,
            uuid = "uuid-123",
          },
        }

        CalibreMetadata.getBookUuid = function(_, path)
          if path == "book.epub" then
            return "uuid-123", 1
          end
        end

        CalibreMetadata.removeBook = function() end
        util.removeFile = function() end
        wireless_inst.sendJsonData = function() end

        finally(function()
          CalibreMetadata.books = orig_books
          CalibreMetadata.getBookUuid = orig_getBookUuid
          CalibreMetadata.removeBook = orig_removeBook
          util.removeFile = orig_removeFile
          G_reader_settings:delete("inbox_dir")
        end)

        -- In wireless.lua:681:
        -- titles = titles .. "\n" .. CalibreMetadata.books[index].title
        -- When title is nil, this crashes with "attempt to concatenate field 'title' (a nil value)".
        -- Expected: deleting a book with title = nil should proceed without crashing.
        wireless_inst:deleteBook({ lpaths = { "book.epub" } })
      end
    )
  end)
end)
