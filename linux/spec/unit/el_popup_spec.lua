describe("Greek KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/el_popup")
  end)

  it("should return Greek key popup table", function()
    assert.is_table(Popup)
  end)
end)
