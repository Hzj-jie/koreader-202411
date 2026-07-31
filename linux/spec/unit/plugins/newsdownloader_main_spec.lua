describe("NewsDownloader main plugin module", function()
  local NewsDownloader

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    NewsDownloader = require("plugins/newsdownloader.koplugin/main")
    NewsDownloader.path = "plugins/newsdownloader.koplugin"
  end)

  it("should initialize NewsDownloader plugin and register to main menu", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = NewsDownloader:new({ ui = mock_ui, path = "plugins/newsdownloader.koplugin" })
    inst:init()

    local menu_items = {}
    inst:addToMainMenu(menu_items)
    assert.is_table(menu_items.news_downloader)
    assert.is_function(menu_items.news_downloader.sub_item_table_func)

    local sub_items = menu_items.news_downloader.sub_item_table_func()
    assert.is_table(sub_items)
    assert.is_true(#sub_items >= 3)
  end)

  it("should perform lazy initialization and configure paths", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = NewsDownloader:new({ ui = mock_ui, path = "plugins/newsdownloader.koplugin" })
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

    local inst = NewsDownloader:new({ ui = mock_ui, path = "plugins/newsdownloader.koplugin" })
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

    local inst = NewsDownloader:new({ ui = mock_ui, path = "plugins/newsdownloader.koplugin" })
    inst.download_dir = "/tmp/news/"

    inst:onCloseDocument()
  end)
end)
