describe("Kindle KeyboardLayout module", function()
  local Layout

  setup(function()
    require("commonrequire")
    Layout = require("device/kindle/keyboard_layout")
  end)

  it("should return Kindle keyboard layout matrix", function()
    assert.is_table(Layout)
  end)
end)
