describe("ExternalKeyboard event map module", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("plugins/externalkeyboard.koplugin/event_map_keyboard")
  end)

  it("should return keyboard event map table", function()
    assert.is_table(EventMap)
  end)
end)
