describe("NewsDownloader FeedView module", function()
  local FeedView

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FeedView = require("plugins/newsdownloader.koplugin/feed_view")
  end)

  it("should create feed item structure and trigger callbacks", function()
    local edit_called, attr_name, attr_val
    local delete_called_id

    local edit_cb = function(id, name, val)
      edit_called = true
      attr_name = name
      attr_val = val
    end
    local delete_cb = function(id)
      delete_called_id = id
    end

    local feed = {
      "https://example.com/rss",
      limit = 10,
      download_full_article = true,
      include_images = true,
      enable_filter = false,
      filter_element = "article",
    }

    local item = FeedView:getItem(1, feed, edit_cb, delete_cb)
    assert.is_table(item)

    item[1].callback()
    assert.is_true(edit_called)
    assert.are.equal(FeedView.URL, attr_name)

    item[#item].callback()
    assert.are.equal(1, delete_called_id)
  end)

  it("should return nil for invalid feed item without url", function()
    local feed = { limit = 5 }
    local item = FeedView:getItem(1, feed, function() end, function() end)
    assert.is_nil(item)
  end)

  it("should build feed list view content", function()
    local feed_config = {
      {
        "https://example.com/rss1",
        limit = 5,
      },
      {
        "https://example.com/rss2",
        limit = 10,
      },
    }

    local clicked_content
    local list_cb = function(content)
      clicked_content = content
    end

    local list = FeedView:getList(
      feed_config,
      list_cb,
      function() end,
      function() end
    )
    assert.is_table(list)
    assert.is_true(#list > 0)

    list[1].callback()
    assert.is_table(clicked_content)
  end)
end)
