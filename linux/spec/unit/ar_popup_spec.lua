describe("Arabic KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/ar_popup")
  end)

  it("should return Arabic key popup table", function()
    assert.is_table(Popup)
  end)
end)
