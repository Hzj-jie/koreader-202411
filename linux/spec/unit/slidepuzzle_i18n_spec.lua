describe("SlidePuzzleI18n module", function()
  local I18n

  setup(function()
    require("commonrequire")
    I18n = require("plugins/slidepuzzle.koplugin/slidepuzzle_i18n")
  end)

  it("should expose I18n translation functions", function()
    assert.is_table(I18n)
  end)
end)
