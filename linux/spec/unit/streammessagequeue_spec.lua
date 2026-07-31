describe("StreamMessageQueue module", function()
  local StreamMessageQueue

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    StreamMessageQueue = require("ui/message/streammessagequeue")
  end)

  it("should initialize StreamMessageQueue instance with host and port", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
    assert.is_table(smq)
    assert.are.equal("127.0.0.1", smq.host)
    assert.are.equal(8080, smq.port)
  end)

  it("should handle stopping message queue and destroying handles", function()
    local smq = StreamMessageQueue:new({ host = "127.0.0.1", port = 8080 })
    smq.poller = {}
    smq.socket = {}

    -- Should not throw on stop
    smq:stop()
    assert.is_not_nil(smq)
  end)
end)
