describe("FeedConfig module", function()
  local FeedConfig

  setup(function()
    require("commonrequire")
    FeedConfig = require("plugins/newsdownloader.koplugin/feed_config")
  end)

  it("should return feed configuration table", function()
    assert.is_table(FeedConfig)
  end)
end)
