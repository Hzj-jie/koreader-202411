describe("Ukrainian KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/uk_popup")
  end)

  it("should return Ukrainian key popup table", function()
    assert.is_table(Popup)
  end)
end)
