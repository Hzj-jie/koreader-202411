local ffi = require("ffi")
local socket = require("socket")

describe("StreamMessageQueueServer module", function()
  local StreamMessageQueueServer, StreamMessageQueue, czmq
  local active_servers, active_clients

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    require("ffi/zeromq_h")
    ffi.cdef([[
      zframe_t *zframe_new(const void *data, size_t size);
    ]])
    czmq = ffi.loadlib("czmq", "4")
    StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
    StreamMessageQueue = require("ui/message/streammessagequeue")
  end)

  before_each(function()
    active_servers = {}
    active_clients = {}
  end)

  after_each(function()
    for _, cli in ipairs(active_clients) do
      pcall(function() cli:stop() end)
    end
    for _, srv in ipairs(active_servers) do
      pcall(function() srv:stop() end)
    end
  end)

  local function getTestPort()
    return 21000 + (ffi.C.getpid() % 10000)
  end

  it("should initialize StreamMessageQueueServer instance", function()
    local server = StreamMessageQueueServer:new({
      host = "127.0.0.1",
      port = 8080,
    })
    assert.is_table(server)
    assert.are.equal("127.0.0.1", server.host)
    assert.are.equal(8080, server.port)
  end)

  it("should handle stop lifecycle safely when unstarted", function()
    local server = StreamMessageQueueServer:new({
      host = "127.0.0.1",
      port = 8080,
    })
    server:stop()
    assert.is_nil(server.socket)
    assert.is_nil(server.poller)
  end)

  it("should handle error when binding to invalid host or port", function()
    local server = StreamMessageQueueServer:new({
      host = "invalid_hostname_99999",
      port = -1,
    })
    assert.has_error(function()
      server:start()
    end)
    if server.socket then
      czmq.zsock_destroy(ffi.new("zsock_t *[1]", server.socket))
      server.socket = nil
    end
  end)

  it("should handle handleZframe for valid data and empty frames", function()
    local server = StreamMessageQueueServer:new({ host = "127.0.0.1", port = 8080 })

    local test_frame = czmq.zframe_new("server_data", 11)
    local data = server:handleZframe(test_frame)
    assert.are.equal("server_data", data)

    local empty_frame = czmq.zframe_new("", 0)
    local empty_data = server:handleZframe(empty_frame)
    assert.is_nil(empty_data)
  end)

  it("should bind, receive request in waitEvent, and send response to client", function()
    local port = getTestPort()
    local srv = StreamMessageQueueServer:new({ host = "127.0.0.1", port = port })
    srv:start()
    table.insert(active_servers, srv)

    assert.is_not_nil(srv.socket)
    assert.is_not_nil(srv.poller)

    local cli = StreamMessageQueue:new({ host = "127.0.0.1", port = port })
    cli:start()
    table.insert(active_clients, cli)

    cli:send("hello server req")

    local received_req, received_id
    srv.receiveCallback = function(req, id)
      received_req = req
      received_id = id
    end

    socket.sleep(0.05)
    srv:waitEvent()
    assert.are.equal("hello server req", received_req)
    assert.is_not_nil(received_id)

    -- Send response with binary / null byte data
    srv:send("resp\0ack", received_id)

    local received_resp
    cli.receiveCallback = function(pkgs)
      received_resp = table.concat(pkgs)
    end

    socket.sleep(0.05)
    cli:waitEvent()
    assert.are.equal("resp\0ack", received_resp)
  end)

  it("should not trigger receiveCallback in waitEvent when no requests are waiting", function()
    local port = getTestPort() + 1
    local srv = StreamMessageQueueServer:new({ host = "127.0.0.1", port = port })
    srv:start()
    table.insert(active_servers, srv)

    local called = false
    srv.receiveCallback = function()
      called = true
    end

    srv:waitEvent()
    assert.is_false(called)
  end)
end)
