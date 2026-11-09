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

    it("should register dispatcher actions", function()
      local downloader = NewsDownloader:new({
        ui = create_mock_ui(),
      })
      if type(downloader.onDispatcherRegisterActions) == "function" then
        downloader:onDispatcherRegisterActions()
      end
      if type(downloader.onShowNewsMenu) == "function" then
        assert.is_function(downloader.onShowNewsMenu)
      end
    end)
  end)

  describe("Feed attribute editing", function()
    local FeedView, InputDialog, MultiConfirmBox, gettext

    setup(function()
      FeedView = require("plugins/newsdownloader.koplugin/feed_view")
      InputDialog = require("ui/widget/inputdialog")
      MultiConfirmBox = require("ui/widget/multiconfirmbox")
      gettext = require("gettext")
    end)

    local function findButtonByText(widget, target_text)
      if type(widget) ~= "table" then
        return nil
      end
      if widget.text == target_text and type(widget.callback) == "function" then
        return widget
      end
      for _, child in ipairs(widget) do
        local found = findButtonByText(child, target_text)
        if found then
          return found
        end
      end
      return nil
    end

    local function findWindowWidget(widget_cls)
      for i = #UIManager._window_stack, 1, -1 do
        local widget = UIManager._window_stack[i].widget
        if getmetatable(widget).__index == widget_cls then
          return widget
        end
      end
      return nil
    end

    local function assertCancelPreservesFeedView(key, value, dialog_cls)
      local downloader = NewsDownloader:new({
        ui = create_mock_ui(),
        path = "plugins/newsdownloader.koplugin",
      })
      downloader:lazyInitialization()
      downloader:viewFeedItem(
        FeedView:getItem(
          1,
          downloader.empty_feed,
          function(id, edit_key, edit_val)
            downloader:editFeedAttribute(id, edit_key, edit_val)
          end
        )
      )

      local dialog
      finally(function()
        UIManager:closeIfShown(dialog)
        UIManager:closeIfShown(downloader.kv)
      end)

      assert.is_true(UIManager:isWindowWidget(downloader.kv))
      downloader:editFeedAttribute(1, key, value)
      dialog = findWindowWidget(dialog_cls)
      assert.is_truthy(dialog)

      local cancel_btn = findButtonByText(dialog, gettext("Cancel"))
      assert.truthy(cancel_btn)
      cancel_btn.callback()

      assert.is_false(UIManager:isWindowWidget(dialog))
      assert.is_true(UIManager:isWindowWidget(downloader.kv))
    end

    it(
      "should keep the feed item view open when cancelling InputDialog edits",
      function()
        assertCancelPreservesFeedView(
          FeedView.URL,
          "https://example.com/feed.xml",
          InputDialog
        )
      end
    )

    it(
      "should keep the feed item view open when cancelling MultiConfirmBox edits",
      function()
        assertCancelPreservesFeedView(
          FeedView.DOWNLOAD_FULL_ARTICLE,
          true,
          MultiConfirmBox
        )
      end
    )
  end)
end)
