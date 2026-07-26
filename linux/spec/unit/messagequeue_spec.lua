describe("MessageQueue base module", function()
  local MessageQueue

  setup(function()
    require("commonrequire")
    MessageQueue = require("ui/message/messagequeue")
  end)

  it("should initialize MessageQueue", function()
    local mq = MessageQueue:new()
    assert.is_table(mq)
  end)
end)
