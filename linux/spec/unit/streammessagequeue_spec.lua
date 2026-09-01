describe("StreamMessageQueue module", function()
  local StreamMessageQueue

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    StreamMessageQueue = require("ui/message/streammessagequeue")
  end)

  it(
    "should initialize StreamMessageQueue instance with host and port",
    function()
      local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
      assert.is_table(smq)
      assert.are.equal("127.0.0.1", smq.host)
      assert.are.equal(8080, smq.port)
    end
  )

  it("should handle stopping message queue and destroying handles", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
    smq.poller = nil
    smq.socket = nil

    -- Should not throw on stop
    smq:stop()
    assert.is_not_nil(smq)
  end)

  it("should throw error on invalid connection parameters in start", function()
    local smq = StreamMessageQueue:new({ host = "invalid.domain.99999", port = -1 })
    assert.has_error(function()
      smq:start()
    end)
  end)
end)
