describe("Kindle K3 Alt and Top Row event map", function()
  local EventMap

  setup(function()
    require("commonrequire")
    EventMap = require("device/kindle/k3_alt_and_top_row")
  end)

  it("should return Kindle 3 alt and top row mapping table", function()
    assert.is_table(EventMap)
  end)
end)
