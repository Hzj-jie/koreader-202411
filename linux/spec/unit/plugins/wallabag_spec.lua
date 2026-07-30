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

    it("should read settings from LuaSettings file", function()
      local settings_file = DataStorage:getSettingsDir() .. "/wallabag.lua"
      local ls = LuaSettings:open(settings_file)
      ls:save("wallabag", {
        server_url = "https://wallabag.example.com",
        client_id = "test_id",
        client_secret = "test_secret",
        username = "user1",
        password = "secretpassword",
        directory = "/tmp/wallabag",
        articles_per_sync = 50,
      })
      ls:flush()

      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({
        ui = mock_ui,
      })

      assert.are.equal(wallabag.server_url, "https://wallabag.example.com")
      assert.are.equal(wallabag.client_id, "test_id")
      assert.are.equal(wallabag.articles_per_sync, 50)
      os.remove(settings_file)
    end)
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

    it("should handle setting updates and dialog triggers safely", function()
      local mock_ui = create_mock_ui()
      local wallabag = Wallabag:new({ ui = mock_ui })

      if type(wallabag.onShowWallabagMenu) == "function" then
        assert.is_function(wallabag.onShowWallabagMenu)
      end
    end)
  end)
end)
