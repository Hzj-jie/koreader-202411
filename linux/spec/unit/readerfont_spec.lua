describe("ReaderFont module", function()
  local ReaderFont

  setup(function()
    require("commonrequire")
    ReaderFont = require("apps/reader/modules/readerfont")
  end)

  it("should initialize ReaderFont class", function()
    assert.is_table(ReaderFont)
  end)
end)
