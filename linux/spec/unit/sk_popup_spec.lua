describe("Slovak KeyPopup data module", function()
  local Popup

  setup(function()
    require("commonrequire")
    Popup = require("ui/data/keyboardlayouts/keypopup/sk_popup")
  end)

  it("should return Slovak key popup table", function()
    assert.is_table(Popup)
  end)
end)
