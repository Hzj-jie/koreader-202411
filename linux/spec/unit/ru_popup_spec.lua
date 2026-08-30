describe("Russian KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/ru_popup")
  end)

  it("should return Russian key popup table", function()
    assert.is_table(Popup)
  end)
end)
