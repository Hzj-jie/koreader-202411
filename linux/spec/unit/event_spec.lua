describe("Event", function()
  local Event

  setup(function()
    require("commonrequire")
    Event = require("ui/event")
  end)

  it("should create new Event with handler name and args", function()
    local ev = Event:new("GotoPage", 5, "param")
    assert.are.equal("onGotoPage", ev.handler)
    assert.are.equal(2, ev.args.n)
    assert.are.equal(5, ev.args[1])
    assert.are.equal("param", ev.args[2])
    assert.is_false(ev:isUserInput())
  end)

  it("should convert event to user input via asUserInput", function()
    local ev = Event:new("Tap")
    assert.is_false(ev:isUserInput())

    local ret = ev:asUserInput()
    assert.are.equal(ev, ret)
    assert.is_true(ev:isUserInput())
  end)
end)
