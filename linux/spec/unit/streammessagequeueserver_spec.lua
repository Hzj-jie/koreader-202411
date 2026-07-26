describe("StreamMessageQueueServer module", function()
  local StreamMessageQueueServer

  setup(function()
    require("commonrequire")
    StreamMessageQueueServer = require("ui/message/streammessagequeueserver")
  end)

  it("should initialize StreamMessageQueueServer", function()
    local server = StreamMessageQueueServer:new()
    assert.is_table(server)
  end)
end)
