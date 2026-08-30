describe("NewsDownloader handler module", function()
  local Handler

  setup(function()
    require("commonrequire")
    Handler = require("plugins/newsdownloader.koplugin/lib/handler")
  end)

  it("should expose newsdownloader handler functions", function()
    assert.is_table(Handler)
  end)
end)
