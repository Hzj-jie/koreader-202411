describe("ReaderStyleTweak module", function()
  local ReaderStyleTweak

  setup(function()
    require("commonrequire")
    ReaderStyleTweak = require("apps/reader/modules/readerstyletweak")
  end)

  it("should initialize ReaderStyleTweak class", function()
    assert.is_table(ReaderStyleTweak)
  end)
end)
