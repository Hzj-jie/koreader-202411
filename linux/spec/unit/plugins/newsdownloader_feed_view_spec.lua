describe("NewsDownloader FeedView module", function()
  local FeedView

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FeedView = require("plugins/newsdownloader.koplugin/feed_view")
  end)

  it("should create feed item structure and trigger all attribute callbacks", function()
    local edits = {}
    local delete_called_id

    local edit_cb = function(id, name, val)
      edits[name] = { id = id, val = val }
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
    assert.are.equal(8, #item) -- 6 attributes + separator + delete

    -- Test URL callback (item 1)
    item[1].callback()
    assert.are.equal(1, edits[FeedView.URL].id)
    assert.are.equal("https://example.com/rss", edits[FeedView.URL].val)

    -- Test Limit callback (item 2)
    item[2].callback()
    assert.are.equal(1, edits[FeedView.LIMIT].id)
    assert.are.equal(10, edits[FeedView.LIMIT].val)

    -- Test Download full article callback (item 3)
    item[3].callback()
    assert.are.equal(1, edits[FeedView.DOWNLOAD_FULL_ARTICLE].id)
    assert.are.equal(true, edits[FeedView.DOWNLOAD_FULL_ARTICLE].val)

    -- Test Include images callback (item 4)
    item[4].callback()
    assert.are.equal(1, edits[FeedView.INCLUDE_IMAGES].id)
    assert.are.equal(true, edits[FeedView.INCLUDE_IMAGES].val)

    -- Test Enable filter callback (item 5)
    item[5].callback()
    assert.are.equal(1, edits[FeedView.ENABLE_FILTER].id)
    assert.are.equal(false, edits[FeedView.ENABLE_FILTER].val)

    -- Test Filter element callback (item 6)
    item[6].callback()
    assert.are.equal(1, edits[FeedView.FILTER_ELEMENT].id)
    assert.are.equal("article", edits[FeedView.FILTER_ELEMENT].val)

    -- Test Delete callback (item 8)
    item[8].callback()
    assert.are.equal(1, delete_called_id)
  end)

  it("should omit delete feed button when delete_feed_callback is nil", function()
    local feed = {
      "https://example.com/rss",
      limit = 5,
    }
    local item = FeedView:getItem(1, feed, function() end, nil)
    assert.is_table(item)
    assert.are.equal(6, #item) -- exactly 6 attributes, no separator or delete
  end)

  it("should build feed list view content and invoke callback with flattened content", function()
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
    assert.are.equal(4, #list) -- 2 items + 2 dividers
    assert.are.equal("https://example.com/rss1", list[1][1])
    assert.are.equal("---", list[2])
    assert.are.equal("https://example.com/rss2", list[3][1])
    assert.are.equal("---", list[4])

    list[1].callback()
    assert.is_table(clicked_content)
    assert.is_true(#clicked_content > 0)
  end)

  it("should return nil when feed item is missing limit or both url and limit", function()
    local item_no_limit = FeedView:getItem(1, { "https://example.com/rss" }, function() end)
    assert.is_nil(item_no_limit)

    local item_empty = FeedView:getItem(1, {}, function() end)
    assert.is_nil(item_empty)
  end)

  it("should default include_images and enable_filter to false when omitted", function()
    local feed = {
      "https://example.com/rss",
      limit = 5,
    }
    local item = FeedView:getItem(1, feed, function() end)
    assert.is_table(item)
    -- Attribute 4: Include images
    assert.are.equal(false, item[4][2])
    -- Attribute 5: Enable filter
    assert.are.equal(false, item[5][2])
  end)
end)
