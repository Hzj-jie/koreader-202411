describe("StreamMessageQueue module", function()
  local StreamMessageQueue

  setup(function()
    require("commonrequire")
    StreamMessageQueue = require("ui/message/streammessagequeue")
  end)

  it("should initialize StreamMessageQueue", function()
    local smq = StreamMessageQueue:new()
    assert.is_table(smq)
  end)
end)
