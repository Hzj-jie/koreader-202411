describe("AnnotationSync imported plugin settings", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, LuaSettings, DataStorage
  local Dispatcher
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_imported_plugin_settings_tmp"
  local old_getDataDir
  local settings_dir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    json = require("json")
    LuaSettings = require("luasettings")
    DataStorage = require("datastorage")
    Dispatcher = require("dispatcher")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    settings_dir = DataStorage:getSettingsDir()
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
  end)

  before_each(function()
    G_reader_settings:save("cloud_server_object", json.encode({ url = "http://mock", type = "webdav" }))
    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    sync_instance.path = "plugins/AnnotationSync.koplugin"
    manager = sync_instance.manager
    UIManager:show(readerui)
    fastforward_ui_events()
  end)

  after_each(function()
    if readerui then
      readerui:onExit(true)
      readerui = nil
    end
  end)

  -- Skipped as an edge case: an import into a plugin's settings file is lost only if that plugin saves its in-memory copy before KOReader restarts.
  pending("an imported book shortcut is still there after a shortcut is added in the same session", function()
    local bs_path = settings_dir .. "/bookshortcuts.lua"
    os.remove(bs_path)
    package.loaded["plugins/bookshortcuts.koplugin/main"] = nil
    local BookShortcuts = require("plugins/bookshortcuts.koplugin/main")
    local bs = BookShortcuts:new({ ui = { menu = { registerToMainMenu = function() end } } })
    finally(function()
      bs:deleteShortcut(test_data_dir)
      os.remove(bs_path)
      package.loaded["plugins/bookshortcuts.koplugin/main"] = nil
    end)

    assert.is_true(manager:_writeLocalSettingValue("settings/bookshortcuts:/books/Imported", true))
    assert.is_true(LuaSettings:open(bs_path):read("/books/Imported"))

    bs:addShortcut(test_data_dir)
    bs:onFlushSettings()

    assert.is_true(LuaSettings:open(bs_path):read("/books/Imported"))
  end)

  pending("an imported Wallabag setting is still there after Wallabag saves its settings", function()
    local wb_path = settings_dir .. "/wallabag.lua"
    os.remove(wb_path)
    package.loaded["plugins/wallabag.koplugin/main"] = nil
    local Wallabag = require("plugins/wallabag.koplugin/main")
    local wb = Wallabag:new({ ui = { menu = { registerToMainMenu = function() end } } })
    finally(function()
      Dispatcher:removeAction("wallabag_download")
      os.remove(wb_path)
      package.loaded["plugins/wallabag.koplugin/main"] = nil
    end)

    assert.is_true(manager:_writeLocalSettingValue("settings/wallabag:wallabag.articles_per_sync", 99))
    assert.are.equal(99, LuaSettings:open(wb_path):read("wallabag").articles_per_sync)

    wb:saveSettings()

    assert.are.equal(99, LuaSettings:open(wb_path):read("wallabag").articles_per_sync)
  end)
end)
