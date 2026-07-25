describe("ReaderProgress module", function()
  local ReaderProgress

  setup(function()
    require("commonrequire")
    ReaderProgress = require("plugins/statistics.koplugin/readerprogress")
  end)

  it("should initialize ReaderProgress class", function()
    assert.is_table(ReaderProgress)
  end)
end)
