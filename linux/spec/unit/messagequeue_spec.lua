describe("MessageQueue base module", function()
  local MessageQueue

  setup(function()
    require("commonrequire")
    MessageQueue = require("ui/message/messagequeue")
  end)

  it("should initialize MessageQueue", function()
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
end)
