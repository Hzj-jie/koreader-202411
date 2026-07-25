describe("Android EventMap module", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("device/android/event_map")
  end)

  it("should return Android event map table", function()
    assert.is_table(EventMap)
  end)
end)
