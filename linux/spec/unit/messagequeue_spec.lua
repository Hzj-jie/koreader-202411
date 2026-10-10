describe("MessageQueue base module", function()
  local MessageQueue, ffi, czmq

  setup(function()
    require("commonrequire")
    MessageQueue = require("ui/message/messagequeue")
    ffi = require("ffi")
    require("ffi/zeromq_h")
    ffi.cdef([[
      void *zhash_first(zhash_t *);
      void *zhash_next(zhash_t *);
    ]])
    czmq = ffi.loadlib("czmq", "4")
  end)

  it("should initialize MessageQueue subclass and call init", function()
    local init_called = false
    local SubQueue = MessageQueue:extend({
      init = function(self)
        init_called = true
      end,
    })

    local mq = SubQueue:new()
    assert.is_table(mq)
    assert.is_true(init_called)
    assert.are.same({}, mq.messages)
  end)

  it("should provide default no-op methods", function()
    local mq = MessageQueue:new()
    assert.has_no.errors(function()
      mq:init()
      mq:start()
      mq:stop()
      mq:waitEvent()
    end)
  end)

  it("should return nil when handleZMsgs is called with empty messages", function()
    local mq = MessageQueue:new()
    assert.is_nil(mq:handleZMsgs({}))
  end)

  it("should handle DELIVER message and return FileDeliver event", function()
    local mq = MessageQueue:new()
    local msg = czmq.zmsg_new()
    czmq.zmsg_addmem(msg, "DELIVER\0", #"DELIVER" + 1)
    czmq.zmsg_addmem(msg, "test.epub\0", #"test.epub" + 1)
    czmq.zmsg_addmem(msg, "/path/to/test.epub\0", #"/path/to/test.epub" + 1)

    local ev = mq:handleZMsgs({ msg })
    assert.is_not_nil(ev)
    assert.are.equal("onFileDeliver", ev.handler)
    assert.are.equal("test.epub", ev.args[1])
    assert.are.equal("/path/to/test.epub", ev.args[2])
  end)

  it("should handle ENTER message with header and return ZyreEnter event", function()
    local mq = MessageQueue:new()
    local msg = czmq.zmsg_new()
    czmq.zmsg_addmem(msg, "ENTER\0", #"ENTER" + 1)
    czmq.zmsg_addmem(msg, "peer-uuid-123\0", #"peer-uuid-123" + 1)
    czmq.zmsg_addmem(msg, "alice\0", #"alice" + 1)
    czmq.zmsg_addmem(msg, "", 0)
    czmq.zmsg_addmem(msg, "tcp://192.168.1.5:5555\0", #"tcp://192.168.1.5:5555" + 1)

    local ev = mq:handleZMsgs({ msg })
    assert.is_not_nil(ev)
    assert.are.equal("onZyreEnter", ev.handler)
    assert.are.equal("peer-uuid-123", ev.args[1])
    assert.are.equal("alice", ev.args[2])
    assert.is_table(ev.args[3])
    assert.are.equal("tcp://192.168.1.5:5555", ev.args[4])
  end)

  it("should return nil for unhandled zmq command", function()
    local mq = MessageQueue:new()
    local msg = czmq.zmsg_new()
    czmq.zmsg_addmem(msg, "PING\0", #"PING" + 1)

    local ev = mq:handleZMsgs({ msg })
    assert.is_nil(ev)
  end)

  it("should assign distinct messages table to instance rather than mutating prototype", function()
    local q1 = MessageQueue:new()
    local q2 = MessageQueue:new()

    -- Each instance should own its own messages table directly
    assert.is_not_nil(rawget(q1, "messages"))
    assert.are_not.equal(q1.messages, q2.messages)

    q1.messages["test_key"] = "test_value"
    assert.is_nil(q2.messages["test_key"])
  end)
end)
