describe("WpaSupplicant network module", function()
  local WpaSupplicant

  setup(function()
    require("commonrequire")
    WpaSupplicant = require("ui/network/wpa_supplicant")
  end)

  it("should expose WpaSupplicant helper module", function()
    assert.is_table(WpaSupplicant)
  end)
end)
