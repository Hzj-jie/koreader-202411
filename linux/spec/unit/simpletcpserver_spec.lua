describe("SimpleTCPServer module", function()
  local SimpleTCPServer
  local socket

  setup(function()
    require("commonrequire")
    SimpleTCPServer = require("ui/message/simpletcpserver")
    socket = require("socket")
  end)

  it("should initialize SimpleTCPServer instance", function()
    local srv = SimpleTCPServer:new({
      host = "127.0.0.1",
      port = 8080,
    })
    assert.is_table(srv)
    assert.are.equal("127.0.0.1", srv.host)
    assert.are.equal(8080, srv.port)
  end)

  it("should start on random available port and stop cleanly", function()
    local srv = SimpleTCPServer:new({
      host = "127.0.0.1",
      port = 0, -- bind to random port
    })
    srv:start()
    assert.is_not_nil(srv.server)
    assert.is_true(srv.port > 0)

    srv:stop()
  end)

  it("should handle waitEvent safely when unstarted or no connection", function()
    local srv = SimpleTCPServer:new({
      host = "127.0.0.1",
      port = 0,
    })
    -- When server is nil
    assert.has_no.errors(function()
      srv:waitEvent()
    end)

    -- When server is started but no client connects
    srv:start()
    assert.has_no.errors(function()
      srv:waitEvent()
    end)
    srv:stop()
  end)

  it("should process incoming request lines and invoke receiveCallback", function()
    local srv = SimpleTCPServer:new({
      host = "127.0.0.1",
      port = 8080,
    })

    local client_closed = false
    local sent_response = nil
    local line_idx = 0
    local lines = { "GET / HTTP/1.1", "Host: localhost", "" }

    local mock_client = {
      settimeout = function() end,
      receive = function(self, pattern)
        line_idx = line_idx + 1
        return lines[line_idx]
      end,
      send = function(self, data)
        sent_response = data
      end,
      close = function(self)
        client_closed = true
      end,
    }

    local mock_server = {
      accept = function()
        return mock_client
      end,
      close = function() end,
    }
    srv.server = mock_server

    local received_data = nil
    srv.receiveCallback = function(data, client)
      received_data = data
      srv:send("HTTP/1.1 200 OK\r\n\r\nHello", client)
    end

    srv:waitEvent()

    assert.is_not_nil(received_data)
    assert.is_truthy(received_data:find("GET / HTTP/1.1", 1, true))
    assert.is_truthy(sent_response:find("200 OK", 1, true))
    assert.is_true(client_closed)
  end)

  it("should handle client timeout gracefully during waitEvent", function()
    local srv = SimpleTCPServer:new({
      host = "127.0.0.1",
      port = 8080,
    })

    local client_closed = false
    local mock_client = {
      settimeout = function() end,
      receive = function()
        return nil, "timeout"
      end,
      close = function()
        client_closed = true
      end,
    }

    srv.server = {
      accept = function()
        return mock_client
      end,
      close = function() end,
    }

    local callback_called = false
    srv.receiveCallback = function()
      callback_called = true
    end

    srv:waitEvent()
    assert.is_true(client_closed)
    assert.is_false(callback_called)
  end)
end)
