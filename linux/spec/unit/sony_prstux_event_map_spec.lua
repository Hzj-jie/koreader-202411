describe("Sony PRST UX EventMap module", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("device/sony-prstux/event_map")
  end)

  it("should return Sony PRST UX event map table", function()
    assert.is_table(EventMap)
  end)
end)
