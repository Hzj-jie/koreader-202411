describe("EventMapKindle4 module", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("device/kindle/event_map_kindle4")
  end)

  it("should return Kindle 4 event map table", function()
    assert.is_table(EventMap)
  end)
end)
