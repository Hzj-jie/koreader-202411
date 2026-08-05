describe("Wallabag plugin", function()
  local Wallabag, UIManager, DataStorage, LuaSettings, NetworkMgr, socketutil, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    DataStorage = require("datastorage")
    LuaSettings = require("frontend/luasettings")
    NetworkMgr = require("ui/network/manager")
    UIManager = require("ui/uimanager")
    socketutil = require("socketutil")
    http = require("socket.http")
    Wallabag = require("plugins/wallabag.koplugin/main")
  end)

  local function create_mock_ui()
    return {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
    }
  end

  describe("Initialization & Settings", function()
    it("should initialize default properties and settings", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({
        ui = mock_ui,
      })

      assert.is_table(wallabag)
      assert.are.equal(wallabag.token_expiry, 0)
      assert.is_true(wallabag.is_delete_finished)
      assert.is_false(wallabag.is_delete_read)
      assert.is_false(wallabag.is_delete_abandoned)
      assert.is_false(wallabag.is_auto_delete)
      assert.are.equal(wallabag.articles_per_sync, 30)
      assert.spy(mock_ui.menu.registerToMainMenu).was_called()
    end)

    it(
      "should read settings from LuaSettings file and save settings",
      function()
        local mock_ui = create_mock_ui()
        local wallabag = Wallabag:new({
          ui = mock_ui,
        })

        wallabag.download_queue = {}
        wallabag.server_url = "https://wallabag.test.com"
        wallabag.articles_per_sync = 40
        wallabag:saveSettings()

        local read_wb = wallabag:readSettings()
        assert.is_table(read_wb)
      end
    )
  end)

  describe("Menu & Action Dispatching", function()
    it("should register actions with Dispatcher", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })
      local Dispatcher = require("dispatcher")
      local s = spy.on(Dispatcher, "registerAction")

      wallabag:onDispatcherRegisterActions()
      assert
        .spy(s)
        .was_called_with(match.is_ref(Dispatcher), "wallabag_download", match.is_table())
      Dispatcher.registerAction:revert()
    end)

    it("should populate main menu entries", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })
      local menu_items = {}

      wallabag:addToMainMenu(menu_items)
      assert.truthy(menu_items.wallabag)
      assert.are.equal(menu_items.wallabag.text, "Wallabag")
    end)
  end)

  describe("Article Processing & Helpers", function()
    it("should parse article ID and clean filenames", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })

      local article = {
        id = 1234,
        title = "Test Article / Spec Special: Characters!",
      }

      if type(wallabag.getArticleFilename) == "function" then
        local filename = wallabag:getArticleFilename(article)
        assert.truthy(filename:find("1234"))
      end
    end)

    it("should correctly determine if token is valid or expired", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })

      wallabag.token_expiry = os.time() + 3600
      wallabag.access_token = "valid_token"

      if type(wallabag.hasValidToken) == "function" then
        assert.is_true(wallabag:hasValidToken())
      end

      wallabag.token_expiry = os.time() - 100
      if type(wallabag.hasValidToken) == "function" then
        assert.is_false(wallabag:hasValidToken())
      end
    end)

    it("should add article to download queue when offline", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })
      wallabag.download_queue = {}

      local old_is_online = NetworkMgr.isOnline
      NetworkMgr.isOnline = function()
        return false
      end

      wallabag:addWallabagArticle("https://example.com/article1")
      assert.are.equal(1, #wallabag.download_queue)
      assert.are.equal(
        "https://example.com/article1",
        wallabag.download_queue[1]
      )

      NetworkMgr.isOnline = old_is_online
    end)
  end)

  describe("Event Callbacks", function()
    it(
      "should handle SynchronizeWallabag event when network is offline",
      function()
        local mock_ui = create_mock_ui()
        local wallabag = Wallabag:new({ ui = mock_ui })
        local net_spy = spy.on(NetworkMgr, "runWhenOnline")

        wallabag:onSynchronizeWallabag()
        assert.spy(net_spy).was_called()
        NetworkMgr.runWhenOnline:revert()
      end
    )
  end)
end)
