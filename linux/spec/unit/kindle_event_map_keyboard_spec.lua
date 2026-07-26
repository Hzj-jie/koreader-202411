describe("Kindle EventMapKeyboard module", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("device/kindle/event_map_keyboard")
  end)

  it("should return Kindle event map keyboard table", function()
    assert.is_table(EventMap)
  end)
end)
