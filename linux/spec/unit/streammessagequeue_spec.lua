local ffi = require("ffi")
local socket = require("socket")

describe("StreamMessageQueue module", function()
  local StreamMessageQueue, StreamMessageQueueServer, czmq
  local active_clients, active_servers

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    require("ffi/zeromq_h")
    ffi.cdef([[
      zframe_t *zframe_new(const void *data, size_t size);
    ]])
    czmq = ffi.loadlib("czmq", "4")
    StreamMessageQueue = require("ui/message/streammessagequeue")
    StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
  end)

  before_each(function()
    active_clients = {}
    active_servers = {}
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
    return 20000 + (ffi.C.getpid() % 10000)
  end

  it("should initialize StreamMessageQueue instance with host and port", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
    assert.is_table(smq)
    assert.are.equal("127.0.0.1", smq.host)
    assert.are.equal(8080, smq.port)
  end)

  it("should handle stopping message queue and destroying handles", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
    smq.poller = nil
    smq.socket = nil

    smq:stop()
    assert.is_not_nil(smq)
  end)

  it("should throw error on invalid connection parameters in start", function()
    local smq = StreamMessageQueue:new({ host = "invalid.domain.99999", port = -1 })
    assert.has_error(function()
      smq:start()
    end)
    if smq.socket then
      czmq.zsock_destroy(ffi.new("zsock_t *[1]", smq.socket))
      smq.socket = nil
    end
  end)

  it("should handle handleZframe for valid data and empty frames", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })

    local test_frame = czmq.zframe_new("test_payload", 12)
    local data = smq:handleZframe(test_frame)
    assert.are.equal("test_payload", data)

    local empty_frame = czmq.zframe_new("", 0)
    local empty_data = smq:handleZframe(empty_frame)
    assert.is_nil(empty_data)
  end)

  it("should connect to server, send data, and receive data in waitEvent", function()
    local port = getTestPort()
    local srv = StreamMessageQueueServer:new({ host = "127.0.0.1", port = port })
    srv:start()
    table.insert(active_servers, srv)

    local cli = StreamMessageQueue:new({ host = "127.0.0.1", port = port })
    cli:start()
    table.insert(active_clients, cli)

    assert.is_string(cli.id)
    assert.is_true(#cli.id > 0)

    -- Client sends data to server
    cli:send("ping from client")

    local srv_received, srv_id
    srv.receiveCallback = function(req, id)
      srv_received = req
      srv_id = id
    end

    socket.sleep(0.05)
    srv:waitEvent()
    assert.are.equal("ping from client", srv_received)
    assert.is_not_nil(srv_id)

    -- Server sends response back to client
    srv:send("pong from server", srv_id)

    local cli_received
    cli.receiveCallback = function(pkgs)
      cli_received = table.concat(pkgs)
    end

    socket.sleep(0.05)
    cli:waitEvent()
    assert.are.equal("pong from server", cli_received)
  end)

  it("should not invoke receiveCallback when no data is waiting", function()
    local port = getTestPort() + 1
    local srv = StreamMessageQueueServer:new({ host = "127.0.0.1", port = port })
    srv:start()
    table.insert(active_servers, srv)

    local cli = StreamMessageQueue:new({ host = "127.0.0.1", port = port })
    cli:start()
    table.insert(active_clients, cli)

    local called = false
    cli.receiveCallback = function()
      called = true
    end

    cli:waitEvent()
    assert.is_false(called)
  end)
end)
