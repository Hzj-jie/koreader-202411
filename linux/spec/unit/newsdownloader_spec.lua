describe("NewsDownloader plugin", function()
  local NewsDownloader

  setup(function()
    require("commonrequire")
    NewsDownloader = require("plugins/newsdownloader.koplugin/main")
  end)

  it("should initialize NewsDownloader plugin class", function()
    assert.is_table(NewsDownloader)
  end)
end)
