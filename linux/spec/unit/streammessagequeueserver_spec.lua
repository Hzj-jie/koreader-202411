describe("StreamMessageQueueServer module", function()
  local StreamMessageQueueServer

  setup(function()
    require("commonrequire")
    package.unloadAll()

    StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
  end)

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
    -- Stopping an unstarted server with nil socket/poller should be a no-op
    server:stop()
  end)

  it("should handle error when binding to invalid host or port", function()
    local server = StreamMessageQueueServer:new({
      host = "invalid_hostname_99999",
      port = -1,
    })
    assert.has_error(function()
      server:start()
    end)
  end)
end)
