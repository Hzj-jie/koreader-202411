describe("FileMessageQueue module", function()
  local ffi = require("ffi")
  local orig_loadlib = ffi.loadlib
  local mock_czmq
  local mock_filemq
  local FileMessageQueue

  setup(function()
    require("commonrequire")

    pcall(
      ffi.cdef,
      [[
      typedef struct _fmq_client_t fmq_client_t;
      typedef struct _fmq_server_t fmq_server_t;
    ]]
    )

    mock_czmq = {
      zpoller_new = function(handle, extra)
        return ffi.cast("void*", 0x1234)
      end,
      zpoller_destroy = function(poller_ptr_array) end,
      zpoller_wait = function(poller, timeout)
        return nil
      end,
      zmsg_size = function(msg)
        if not msg then
          return 0
        end
        local str_cnt = msg.strings and #msg.strings or 0
        local frame_cnt = msg.frames and #msg.frames or 0
        return str_cnt + frame_cnt
      end,
      zmsg_destroy = function(msg_ptr_array) end,
      zmsg_popstr = function(msg)
        if msg and msg.strings and #msg.strings > 0 then
          local s = table.remove(msg.strings, 1)
          return ffi.cast("char *", s)
        end
        return nil
      end,
      zmsg_pop = function(msg)
        if msg and msg.frames and #msg.frames > 0 then
          return table.remove(msg.frames, 1)
        end
        return nil
      end,
      zhash_unpack = function(frame)
        return frame.hash
      end,
      zframe_destroy = function(frame_ptr_array) end,
      zhash_first = function(hash)
        return hash.values and hash.values[1] or nil
      end,
      zhash_cursor = function(hash)
        return hash.keys and hash.keys[1] or nil
      end,
      zhash_next = function(hash)
        return nil
      end,
      zhash_destroy = function(hash_ptr_array) end,
      zstr_free = function(str_ptr_array) end,
    }

    mock_filemq = {
      fmq_client_recv = function(client)
        return nil
      end,
      fmq_client_handle = function(client)
        return ffi.cast("void*", 0x5678)
      end,
      fmq_client_destroy = function(client_ptr_array) end,
      fmq_server_destroy = function(server_ptr_array) end,
    }

    ffi.loadlib = function(lib, version)
      if lib == "czmq" then
        return mock_czmq
      elseif lib == "fmq" then
        return mock_filemq
      end
      if type(orig_loadlib) == "function" then
        return orig_loadlib(lib, version)
      end
      return {}
    end

    package.loaded["ui/message/filemessagequeue"] = nil
    FileMessageQueue = require("ui/message/filemessagequeue")
  end)

  teardown(function()
    ffi.loadlib = orig_loadlib
  end)

  it("should initialize FileMessageQueue class", function()
    assert.is_table(FileMessageQueue)
  end)

  describe("initialization", function()
    it("should instantiate with default options", function()
      local fmq = FileMessageQueue:new()
      assert.is_table(fmq)
      assert.is_nil(fmq.client)
      assert.is_nil(fmq.server)
      assert.is_nil(fmq.filemq)
      assert.is_nil(fmq.fmq_recv)
      assert.is_nil(fmq.poller)
      assert.is_table(fmq.messages)
      assert.are.same({}, fmq.messages)
    end)

    it(
      "should initialize client and setup poller when client is provided",
      function()
        local handle_called_with = nil
        local zpoller_called_with = nil
        local dummy_handle = ffi.cast("void*", 0x1111)
        local dummy_poller = ffi.cast("void*", 0x2222)

        mock_filemq.fmq_client_handle = function(client)
          handle_called_with = client
          return dummy_handle
        end
        mock_czmq.zpoller_new = function(handle, extra)
          zpoller_called_with = { handle = handle, extra = extra }
          return dummy_poller
        end

        local mock_client = ffi.cast("void*", 0x3333)
        local fmq = FileMessageQueue:new({ client = mock_client })

        assert.is_same(mock_client, fmq.client)
        assert.is_same(mock_client, fmq.filemq)
        assert.is_same(mock_filemq.fmq_client_recv, fmq.fmq_recv)
        assert.is_same(dummy_poller, fmq.poller)
        assert.is_same(mock_client, handle_called_with)
        assert.is_same(dummy_handle, zpoller_called_with.handle)
        assert.is_nil(zpoller_called_with.extra)
      end
    )

    it("should initialize server when server is provided", function()
      local mock_server = ffi.cast("void*", 0x4444)
      local fmq = FileMessageQueue:new({ server = mock_server })

      assert.is_same(mock_server, fmq.server)
      assert.is_same(mock_server, fmq.filemq)
      assert.is_nil(fmq.poller)
      assert.is_nil(fmq.fmq_recv)
    end)
  end)

  describe("stop and cleanup", function()
    it(
      "should call destroy functions on stop when client and poller are set",
      function()
        local client_destroyed = false
        local poller_destroyed = false
        mock_filemq.fmq_client_destroy = function(ptr_array)
          client_destroyed = true
        end
        mock_czmq.zpoller_destroy = function(ptr_array)
          poller_destroyed = true
        end

        local fmq = FileMessageQueue:new({ client = ffi.cast("void*", 0x5555) })
        fmq:stop()

        assert.is_true(client_destroyed)
        assert.is_true(poller_destroyed)
      end
    )

    it("should call server destroy on stop when server is set", function()
      local server_destroyed = false
      mock_filemq.fmq_server_destroy = function(ptr_array)
        server_destroyed = true
      end

      local fmq = FileMessageQueue:new({ server = ffi.cast("void*", 0x6666) })
      fmq:stop()

      assert.is_true(server_destroyed)
    end)

    it(
      "should execute stop safely without client, server, or poller",
      function()
        local fmq = FileMessageQueue:new()
        assert.has_no.errors(function()
          fmq:stop()
        end)
      end
    )
  end)

  describe("waitEvent and polling", function()
    it("should return nil when poller is nil", function()
      local fmq = FileMessageQueue:new()
      local res = fmq:waitEvent()
      assert.is_nil(res)
    end)

    it(
      "should return nil and not receive msg when zpoller_wait returns nil",
      function()
        local recv_called = false
        mock_czmq.zpoller_wait = function(poller, timeout)
          assert.is_same(0, timeout)
          return nil
        end
        mock_filemq.fmq_client_recv = function(client)
          recv_called = true
          return nil
        end

        local fmq = FileMessageQueue:new({ client = ffi.cast("void*", 0x7777) })
        local res = fmq:waitEvent()

        assert.is_nil(res)
        assert.is_false(recv_called)
        assert.are.same({}, fmq.messages)
      end
    )

    it(
      "should poll, receive message, and push to queue when zpoller_wait succeeds",
      function()
        local recv_called = false
        local mock_msg =
          { strings = { "DELIVER", "file.epub", "/path/to/file.epub" } }
        mock_czmq.zpoller_wait = function(poller, timeout)
          return ffi.cast("void*", 0x8888)
        end
        mock_filemq.fmq_client_recv = function(client)
          recv_called = true
          return mock_msg
        end

        local fmq = FileMessageQueue:new({ client = ffi.cast("void*", 0x9999) })
        local event = fmq:waitEvent()

        assert.is_true(recv_called)
        assert.is_not_nil(event)
        assert.is_same("onFileDeliver", event.handler)
        assert.is_same("file.epub", event.args[1])
        assert.is_same("/path/to/file.epub", event.args[2])
      end
    )

    it(
      "should not push to queue if fmq_recv returns nil even when poller signals ready",
      function()
        mock_czmq.zpoller_wait = function(poller, timeout)
          return ffi.cast("void*", 0x8888)
        end
        mock_filemq.fmq_client_recv = function(client)
          return nil
        end

        local fmq = FileMessageQueue:new({ client = ffi.cast("void*", 0x9999) })
        local res = fmq:waitEvent()

        assert.is_nil(res)
        assert.are.same({}, fmq.messages)
      end
    )
  end)

  describe("queue persistence and message handling", function()
    it("should handle queued messages sequentially in FIFO order", function()
      local fmq = FileMessageQueue:new()
      fmq.poller = ffi.cast("void*", 0xaaaa)

      local msg1 = { strings = { "DELIVER", "book1.pdf", "/docs/book1.pdf" } }
      local msg2 = { strings = { "DELIVER", "book2.epub", "/docs/book2.epub" } }

      local count = 0
      mock_czmq.zpoller_wait = function(poller, timeout)
        return ffi.cast("void*", 0xbbbb)
      end
      fmq.fmq_recv = function()
        count = count + 1
        if count == 1 then
          return msg1
        elseif count == 2 then
          return msg2
        end
        return nil
      end

      local ev1 = fmq:waitEvent()
      assert.is_same("onFileDeliver", ev1.handler)
      assert.is_same("book1.pdf", ev1.args[1])

      local ev2 = fmq:waitEvent()
      assert.is_same("onFileDeliver", ev2.handler)
      assert.is_same("book2.epub", ev2.args[1])
    end)

    it("should handle ENTER command message", function()
      local fmq = FileMessageQueue:new()
      fmq.poller = ffi.cast("void*", 0xaaaa)

      local header_hash = {
        keys = { ffi.cast("char *", "Key1") },
        values = { ffi.cast("char *", "Val1") },
      }
      local mock_msg = {
        strings = { "ENTER", "node123", "NodeName", "tcp://127.0.0.1:1234" },
        frames = { { hash = header_hash } },
      }

      mock_czmq.zpoller_wait = function(poller, timeout)
        return ffi.cast("void*", 0xbbbb)
      end
      fmq.fmq_recv = function()
        return mock_msg
      end

      local ev = fmq:waitEvent()
      assert.is_not_nil(ev)
      assert.is_same("onZyreEnter", ev.handler)
      assert.is_same("node123", ev.args[1])
      assert.is_same("NodeName", ev.args[2])
      assert.is_table(ev.args[3])
      assert.is_same("Val1", ev.args[3].Key1)
      assert.is_same("tcp://127.0.0.1:1234", ev.args[4])
    end)

    it("should preserve unconsumed messages in the messages queue", function()
      local fmq = FileMessageQueue:new()
      local extra_msg = { strings = { "UNKNOWN_CMD" } }
      table.insert(fmq.messages, extra_msg)

      assert.is_same(1, #fmq.messages)
      local res = fmq:handleZMsgs(fmq.messages)
      assert.is_nil(res)
    end)
  end)
end)
