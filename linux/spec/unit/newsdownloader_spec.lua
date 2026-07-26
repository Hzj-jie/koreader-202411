describe("NewsDownloader plugin", function()
  local NewsDownloader, DataStorage, UIManager, LuaSettings

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    LuaSettings = require("frontend/luasettings")
    UIManager = require("ui/uimanager")
    NewsDownloader = require("plugins/newsdownloader.koplugin/main")
  end)

  local function create_mock_ui()
    return {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
    }
  end

  describe("Initialization & Paths", function()
    it("should initialize default properties and download directory", function()
      local mock_ui = create_mock_ui()
      local downloader = NewsDownloader:new({
        ui = mock_ui,
      })

      assert.is_table(downloader)
      assert.are.equal(downloader.file_extension, ".epub")
      assert.spy(mock_ui.menu.registerToMainMenu).was_called()
    end)

    it("should resolve download directory correctly", function()
      local mock_ui = create_mock_ui()
      local downloader = NewsDownloader:new({
        ui = mock_ui,
        path = "plugins/newsdownloader.koplugin",
      })

      downloader:lazyInitialization()
      assert.is_string(downloader.download_dir)
      assert.truthy(downloader.download_dir:find("news"))
    end)
  end)

  describe("Menu & Submenu Entries", function()
    it("should populate main menu entries", function()
      local mock_ui = create_mock_ui()
      local downloader = NewsDownloader:new({
        ui = mock_ui,
      })
      local menu_items = {}

      downloader:addToMainMenu(menu_items)
      assert.truthy(menu_items.news_downloader)
      assert.truthy(menu_items.news_downloader.text)
    end)
  end)

  describe("Feed Config Loading & Saving", function()
    it("should handle empty or default feed configuration", function()
      local mock_ui = create_mock_ui()
      local downloader = NewsDownloader:new({
        ui = mock_ui,
      })

      if type(downloader.readFeedConfig) == "function" then
        local feeds = downloader:readFeedConfig()
        assert.is_table(feeds)
      end
    end)
  end)
end)
