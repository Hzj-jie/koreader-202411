describe("ReaderTypography module", function()
  local ReaderTypography

  setup(function()
    require("commonrequire")
    ReaderTypography = require("apps/reader/modules/readertypography")
  end)

  it("should initialize ReaderTypography class", function()
    assert.is_table(ReaderTypography)
  end)
end)
