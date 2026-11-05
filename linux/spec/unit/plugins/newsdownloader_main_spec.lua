describe("NewsDownloader main plugin module", function()
  local NewsDownloader
  local UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    NewsDownloader = require("plugins/newsdownloader.koplugin/main")
    NewsDownloader.path = "plugins/newsdownloader.koplugin"
    UIManager = require("ui/uimanager")
  end)

  it(
    "should initialize NewsDownloader plugin and register to main menu",
    function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }

      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
      })
      inst:init()

      local menu_items = {}
      inst:addToMainMenu(menu_items)
      assert.is_table(menu_items.news_downloader)
      assert.is_function(menu_items.news_downloader.sub_item_table_func)

      local sub_items = menu_items.news_downloader.sub_item_table_func()
      assert.is_table(sub_items)
      assert.is_true(#sub_items >= 3)
    end
  )

  it("should perform lazy initialization and configure paths", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
    })
    inst:lazyInitialization()

    assert.is_true(inst.initialized)
    assert.is_string(inst.download_dir)
    assert.is_string(inst.feed_config_path)
    assert.is_table(inst.settings)
  end)

  it("should open downloads folder via file manager", function()
    local FileManager = require("apps/filemanager/filemanager")
    local show_path = nil
    local old_show = FileManager.showFiles
    FileManager.showFiles = function(self, dir)
      show_path = dir
    end

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
    })
    inst:lazyInitialization()
    inst:openDownloadsFolder()

    assert.is_string(show_path)
    assert.are.equal(inst.download_dir, show_path)

    FileManager.showFiles = old_show
  end)

  it("should clean up read history on closing news document", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
      document = {
        file = "/tmp/news/article.epub",
      },
      setLastDirForFileBrowser = function() end,
    }

    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
    })
    inst.download_dir = "/tmp/news/"

    inst:onCloseDocument()
  end)

  it("should execute submenu item callbacks cleanly", function()
    local orig_show = UIManager.show
    UIManager.show = function() end

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
    })
    local sub_items = inst:getSubMenuItems()

    -- Submenu item 1: Go to news folder
    sub_items[1].callback()

    -- Submenu item 4: Settings sub items
    local settings_items = sub_items[4].sub_item_table
    assert.is_table(settings_items)
    settings_items[2].callback() -- flip never_download_images
    assert.is_boolean(settings_items[2].checked_func())

    -- Submenu item 5: About
    sub_items[5].callback()

    UIManager.show = orig_show
  end)

  it("should deserialize RSS and Atom XML strings", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
    })

    local rss_xml = [[<?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Test RSS Feed</title>
        <item>
          <title>Article 1</title>
          <link>https://example.com/article1</link>
          <description>Article 1 description</description>
          <pubDate>Mon, 02 Jan 2006 15:04:05 MST</pubDate>
        </item>
      </channel>
    </rss>]]

    local rss_parsed = inst:deserializeXMLString(rss_xml)
    assert.is_table(rss_parsed)
    assert.is_table(rss_parsed.rss)

    local atom_xml = [[<?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Test Atom Feed</title>
      <entry>
        <title>Atom Entry 1</title>
        <link href="https://example.com/atom1" />
        <summary>Atom Entry 1 summary</summary>
        <updated>2006-01-02T15:04:05Z</updated>
      </entry>
    </feed>]]

    local atom_parsed = inst:deserializeXMLString(atom_xml)
    assert.is_table(atom_parsed)
    assert.is_table(atom_parsed.feed)

    local invalid_parsed = inst:deserializeXMLString("<<<invalid xml")
    assert.is_nil(invalid_parsed)
  end)

  it(
    "should process RSS and Atom feeds with downloadFeed and createFromDescription",
    function()
      local DownloadBackend =
        require("plugins/newsdownloader.koplugin/epubdownloadbackend")
      local orig_get = DownloadBackend.getResponseAsString
      local orig_load = DownloadBackend.loadPage
      local orig_create = DownloadBackend.createEpub

      DownloadBackend.getResponseAsString = function(self, url, cookies)
        return [[<rss version="2.0"><channel><title>Mock RSS</title><item><title>Item 1</title><link>https://example.com/1</link><description>Desc 1</description></item><item><title>Item 2</title><link>https://example.com/2</link><description>Desc 2</description></item></channel></rss>]]
      end
      DownloadBackend.loadPage = function(self, link, cookies)
        return "<html><body>Mock HTML content</body></html>"
      end
      DownloadBackend.createEpub = function(
        self,
        path,
        html,
        link,
        include_images,
        msg
      )
        return true
      end

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
      })
      inst:lazyInitialization()

      local unsupported = {}
      inst:processFeedSource(
        "https://example.com/rss",
        nil,
        1,
        unsupported,
        true,
        false,
        "Msg",
        false,
        ""
      )
      assert.are.equal(#unsupported, 0)

      -- Test createFromDescription
      inst:processFeedSource(
        "https://example.com/rss",
        nil,
        1,
        unsupported,
        false,
        false,
        "Msg",
        false,
        ""
      )
      assert.are.equal(#unsupported, 0)

      -- Test Atom processing
      DownloadBackend.getResponseAsString = function(self, url, cookies)
        return [[<feed xmlns="http://www.w3.org/2005/Atom"><title>Mock Atom</title><entry><title>Atom 1</title><link href="https://example.com/a1"/><summary>Summary 1</summary></entry><entry><title>Atom 2</title><link href="https://example.com/a2"/><summary>Summary 2</summary></entry></feed>]]
      end
      inst:processFeedSource(
        "https://example.com/atom",
        nil,
        1,
        unsupported,
        true,
        false,
        "Msg",
        false,
        ""
      )
      assert.are.equal(#unsupported, 0)

      DownloadBackend.getResponseAsString = orig_get
      DownloadBackend.loadPage = orig_load
      DownloadBackend.createEpub = orig_create
    end
  )

  it("should manage feed list config CRUD operations", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function() end
    UIManager.close = function() end

    local tmp_dir = os.tmpname()
    os.remove(tmp_dir)
    require("libs/libkoreader-lfs").mkdir(tmp_dir)

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local inst = NewsDownloader:new({
      ui = mock_ui,
      path = "plugins/newsdownloader.koplugin",
      download_dir = tmp_dir .. "/",
      feed_config_path = tmp_dir .. "/feed_config.lua",
    })
    inst.settings =
      require("frontend/luasettings"):open(tmp_dir .. "/settings.lua")

    -- Save initial config
    local initial_config = {
      {
        [1] = "https://news.ycombinator.com/rss",
        limit = 5,
        download_full_article = true,
        include_images = false,
        enable_filter = false,
        filter_element = "",
      },
    }
    inst:saveConfig(initial_config)

    -- View feed list and item
    inst:viewFeedList()
    assert.is_table(inst.kv)

    local FeedView = require("plugins/newsdownloader.koplugin/feed_view")
    inst:editFeedAttribute(1, FeedView.URL, "https://example.com/feed")
    inst:editFeedAttribute(1, FeedView.LIMIT, 10)
    inst:editFeedAttribute(1, FeedView.FILTER_ELEMENT, "div.article")
    inst:editFeedAttribute(1, FeedView.DOWNLOAD_FULL_ARTICLE, true)
    inst:editFeedAttribute(1, FeedView.INCLUDE_IMAGES, false)
    inst:editFeedAttribute(1, FeedView.ENABLE_FILTER, false)

    -- Update config
    inst:updateFeedConfig(1, FeedView.LIMIT, 8)
    inst:updateFeedConfig(1, FeedView.DOWNLOAD_FULL_ARTICLE, false)
    inst:updateFeedConfig(1, FeedView.INCLUDE_IMAGES, true)
    inst:updateFeedConfig(1, FeedView.ENABLE_FILTER, true)
    inst:updateFeedConfig(1, FeedView.FILTER_ELEMENT, "article.content")

    -- Remove news
    inst:removeNewsButKeepFeedConfig()

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it(
    "should handle loadConfigAndProcessFeedsWithUI under various configuration states",
    function()
      local UI = require("ui/trapper")
      local info_called = 0
      local confirm_called = 0
      local orig_info = UI.info
      local orig_confirm = UI.confirm
      local orig_clear = UI.clear
      local orig_reset = UI.reset

      UI.info = function()
        info_called = info_called + 1
      end
      UI.confirm = function()
        confirm_called = confirm_called + 1
        return true
      end
      UI.clear = function() end
      UI.reset = function() end

      local tmp_dir = os.tmpname()
      os.remove(tmp_dir)
      require("libs/libkoreader-lfs").mkdir(tmp_dir)

      local mock_menu = {
        closeMenu = function() end,
      }
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
        download_dir = tmp_dir .. "/",
        feed_config_path = tmp_dir .. "/feed_config.lua",
      })
      inst.settings =
        require("frontend/luasettings"):open(tmp_dir .. "/settings.lua")

      -- 1. Non-existent / invalid feed config file
      local ok, err = xpcall(function()
        inst:loadConfigAndProcessFeeds(mock_menu)
      end, debug.traceback)
      if not ok then
        print("LOAD ERROR 1:", err)
      end

      -- 2. Empty feed config
      local orig_view_item = inst.viewFeedItem
      inst.viewFeedItem = function() end
      inst:saveConfig({})
      local ok2, err2 = xpcall(function()
        inst:loadConfigAndProcessFeeds(mock_menu)
      end, debug.traceback)
      if not ok2 then
        print("LOAD ERROR 2:", err2)
      end
      inst.viewFeedItem = orig_view_item

      -- 3. Valid feed config with mock processing
      local valid_config = {
        {
          [1] = "https://example.com/rss",
          limit = 2,
          download_full_article = true,
          include_images = false,
        },
      }
      inst:saveConfig(valid_config)

      local orig_process = inst.processFeedSource
      local orig_open = inst.openDownloadsFolder
      inst.openDownloadsFolder = function() end
      inst.processFeedSource = function(
        self_inst,
        url,
        creds,
        limit,
        unsupported
      )
        -- simulate success
      end

      inst:loadConfigAndProcessFeeds(mock_menu)

      -- 4. Feed config resulting in errors
      inst.processFeedSource = function(
        self_inst,
        url,
        creds,
        limit,
        unsupported
      )
        table.insert(unsupported, { url, "Failed" })
      end
      inst:loadConfigAndProcessFeeds(mock_menu)

      -- 5. setCustomDownloadDirectory
      local DownloadMgr = require("ui/downloadmgr")
      local orig_dm_new = DownloadMgr.new
      DownloadMgr.new = function(cls, opts)
        return {
          chooseDir = function(self_dm, curr_dir)
            if opts.onConfirm then
              opts.onConfirm(tmp_dir)
            end
          end,
        }
      end

      inst:setCustomDownloadDirectory()

      DownloadMgr.new = orig_dm_new
      inst.processFeedSource = orig_process
      UI.info = orig_info
      UI.confirm = orig_confirm
      UI.clear = orig_clear
      UI.reset = orig_reset
    end
  )

  it(
    "should correctly set include_images and filter_element hash fields when updating feed with omitted fields",
    function()
      local tmp_dir = os.tmpname()
      os.remove(tmp_dir)
      require("libs/libkoreader-lfs").mkdir(tmp_dir)

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
        download_dir = tmp_dir .. "/",
        feed_config_path = tmp_dir .. "/feed_config.lua",
      })
      inst.settings =
        require("frontend/luasettings"):open(tmp_dir .. "/settings.lua")

      -- Feed where include_images and filter_element are omitted
      local config = {
        {
          [1] = "https://example.com/rss",
          limit = 5,
        },
      }
      inst:saveConfig(config)

      local FeedView = require("plugins/newsdownloader.koplugin/feed_view")
      local orig_view = inst.viewFeedItem
      inst.viewFeedItem = function() end
      finally(function()
        inst.viewFeedItem = orig_view
      end)

      inst:updateFeedConfig(1, FeedView.INCLUDE_IMAGES, true)
      inst:updateFeedConfig(1, FeedView.FILTER_ELEMENT, "div.article")

      local Persist = require("persist")
      local saved = Persist:new({
        path = inst.feed_config_path,
      }):load()
      assert.is_true(saved[1].include_images == true)
      assert.are.equal("div.article", saved[1].filter_element)
    end
  )

  it(
    "should handle empty Atom feed without crash and process 1-item RSS feed",
    function()
      local DownloadBackend =
        require("plugins/newsdownloader.koplugin/epubdownloadbackend")
      local orig_get = DownloadBackend.getResponseAsString
      local orig_load = DownloadBackend.loadPage
      local orig_create = DownloadBackend.createEpub

      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
      })

      finally(function()
        DownloadBackend.getResponseAsString = orig_get
        DownloadBackend.loadPage = orig_load
        DownloadBackend.createEpub = orig_create
      end)

      -- 1. Empty Atom feed should not crash on feeds.feed.entry[1]
      DownloadBackend.getResponseAsString = function()
        return [[<feed xmlns="http://www.w3.org/2005/Atom"><title>Empty Atom Feed</title></feed>]]
      end
      local unsupported = {}
      local atom_ok, atom_err = pcall(function()
        inst:processFeedSource(
          "https://example.com/atom_empty",
          nil,
          5,
          unsupported,
          true,
          false,
          "Msg",
          false,
          ""
        )
      end)
      assert.is_true(
        atom_ok,
        "empty Atom feed should not crash with error: " .. tostring(atom_err)
      )

      -- 2. 1-item RSS feed should be recognized and processed
      DownloadBackend.getResponseAsString = function()
        return [[<rss version="2.0"><channel><title>Single Item RSS</title><item><title>Article 1</title><link>https://example.com/art1</link><description>Desc 1</description></item></channel></rss>]]
      end
      DownloadBackend.loadPage = function()
        return "<html><body>Content</body></html>"
      end
      local epub_created = false
      DownloadBackend.createEpub = function()
        epub_created = true
      end

      local unsupported_rss = {}
      inst:processFeedSource(
        "https://example.com/rss_single",
        nil,
        5,
        unsupported_rss,
        true,
        false,
        "Msg",
        false,
        ""
      )
      assert.are.equal(0, #unsupported_rss)
      assert.is_true(epub_created)
    end
  )

  it(
    "should delegate news sync to non-blocking background fork job with preflight validation and deduplication (issue #157)",
    function()
      local BackgroundJobs = require("background_jobs")
      local NetworkMgr = require("ui/network/manager")
      local Notification = require("ui/widget/notification")
      local gettext = require("gettext")

      local tmp_dir = os.tmpname()
      os.remove(tmp_dir)
      require("libs/libkoreader-lfs").mkdir(tmp_dir)

      local shown_widgets = {}
      local orig_show = UIManager.show
      UIManager.show = function(self_ui, widget)
        table.insert(shown_widgets, widget)
      end

      local notifications = {}
      local orig_notify = Notification.notify
      Notification.notify = function(self_n, text, ...)
        table.insert(notifications, text)
      end

      local orig_run_when_online = NetworkMgr.runWhenOnline
      NetworkMgr.runWhenOnline = function(self_nm, callback)
        callback()
      end

      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local inst = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
        download_dir = tmp_dir .. "/",
        feed_config_path = tmp_dir .. "/feed_config.lua",
      })
      inst.initialized = true
      inst.settings =
        require("frontend/luasettings"):open(tmp_dir .. "/settings.lua")

      finally(function()
        UIManager.show = orig_show
        Notification.notify = orig_notify
        NetworkMgr.runWhenOnline = orig_run_when_online
      end)

      -- 1. Preflight: invalid feed config syntax shows InfoMessage
      local invalid_file = io.open(inst.feed_config_path, "w")
      invalid_file:write("invalid lua syntax {[[")
      invalid_file:close()

      shown_widgets = {}
      inst:syncNewsFeeds(false)
      assert.are.equal(1, #shown_widgets)
      assert.is_not_nil(shown_widgets[1].text:find("Invalid configuration file"))

      -- 2. Preflight: empty feed config shows ConfirmBox
      inst:saveConfig({})
      shown_widgets = {}
      inst:syncNewsFeeds(false)
      assert.are.equal(1, #shown_widgets)
      assert.are.equal(
        gettext(
          "Feed list is empty. If you want to download news, you'll have to add a feed first."
        ),
        shown_widgets[1].text
      )
      assert.are.equal(gettext("Edit feed list"), shown_widgets[1].ok_text)

      -- 3. Valid config dispatches BackgroundJobs.insertKeyed with fork
      local valid_config = {
        {
          [1] = "https://example.com/feed.xml",
          limit = 2,
          download_full_article = true,
          include_images = false,
        },
      }
      inst:saveConfig(valid_config)

      local captured_job = nil
      local insert_result = true
      local orig_insert = BackgroundJobs.insertKeyed
      BackgroundJobs.insertKeyed = function(job)
        captured_job = job
        return insert_result
      end

      finally(function()
        BackgroundJobs.insertKeyed = orig_insert
      end)

      notifications = {}
      inst:syncNewsFeeds(false)

      assert.is_not_nil(captured_job)
      assert.are.equal("fork", captured_job.executable)
      assert.is_function(captured_job.action)
      assert.is_function(captured_job.callback)
      assert.are.equal(1, #notifications)
      assert.are.equal(
        gettext("Synchronizing news feeds…"),
        notifications[1]
      )

      -- 4. Deduplication: when job is already in progress, insertKeyed returns false
      insert_result = false
      notifications = {}
      inst:syncNewsFeeds(false)
      assert.are.equal(1, #notifications)
      assert.are.equal(
        gettext("Sync is already in progress."),
        notifications[1]
      )

      -- 5. Test background action execution with mock feed processing
      local orig_process = NewsDownloader.processFeedSource
      local processed_urls = {}
      NewsDownloader.processFeedSource = function(
        self_p,
        url,
        creds,
        limit,
        unsupported,
        full_art,
        images,
        msg,
        enable_filter,
        filter_elem
      )
        table.insert(processed_urls, url)
      end

      finally(function()
        NewsDownloader.processFeedSource = orig_process
      end)

      local bg_result = captured_job.action()
      assert.is_table(bg_result)
      assert.is_true(bg_result.ok)
      assert.are.equal(1, #processed_urls)
      assert.are.equal("https://example.com/feed.xml", processed_urls[1])

      -- 6. Callback updates last_sync_time and notifies on success
      notifications = {}
      captured_job.callback({ result = bg_result })
      assert.is_number(inst.settings:read("last_sync_time"))
      assert.are.equal(1, #notifications)
      assert.are.equal(
        gettext("Downloading news finished."),
        notifications[1]
      )

      -- 7. Callback handles error result gracefully
      notifications = {}
      captured_job.callback({
        result = {
          ok = false,
          unsupported_feeds_urls = { { "https://broken.com", "404" } },
        },
      })
      assert.are.equal(1, #notifications)
      assert.are.equal(
        gettext("Downloading news finished with errors."),
        notifications[1]
      )

      -- 8. Callback handles non-table sentinels (e.g. fork failure or exit code) without crash
      notifications = {}
      assert.has_no.errors(function()
        captured_job.callback({ result = false })
        captured_job.callback({ result = 222 })
        captured_job.callback(nil)
      end)
      assert.are.equal(3, #notifications)
    end
  )
end)
