describe("English KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/en_popup")
  end)

  it("should return English key popup table", function()
    assert.is_table(Popup)
  end)
end)
