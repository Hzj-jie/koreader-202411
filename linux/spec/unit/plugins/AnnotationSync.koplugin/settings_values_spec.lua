describe("AnnotationSync settings values and pull menus", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util, LuaSettings, DataStorage, SyncService
  local utils, menus, remote
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_settings_values_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    json = require("json")
    util = require("util")
    LuaSettings = require("luasettings")
    DataStorage = require("datastorage")
    SyncService = require("apps/cloudstorage/syncservice")
    utils = require("plugins/AnnotationSync.koplugin/utils")
    menus = require("plugins/AnnotationSync.koplugin/menus")
    remote = require("plugins/AnnotationSync.koplugin/remote")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
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

  it("getLocalSettingValue reads reader, nested reader, defaults and plugin settings keys", function()
    G_reader_settings:save("rv_number", 77)
    G_reader_settings:save("rv_table", { inner = { leaf = "x" } })
    local p_s = LuaSettings:open(DataStorage:getSettingsDir() .. "/rv_plugin.lua")
    p_s:save("a", { b = 5 })
    p_s:flush()
    G_defaults:save("RV_DEFAULT", 9)
    G_defaults:flush()

    finally(function()
      G_reader_settings:delete("rv_number")
      G_reader_settings:delete("rv_table")
      os.remove(DataStorage:getSettingsDir() .. "/rv_plugin.lua")
      G_defaults:delete("RV_DEFAULT")
      G_defaults:flush()
      os.remove(test_data_dir .. "/defaults.custom.lua")
    end)

    local caches = {}
    assert.are.equal(77, manager:getLocalSettingValue("reader:rv_number", caches))
    assert.are.equal("x", manager:getLocalSettingValue("reader:rv_table.inner.leaf", caches))
    assert.are.equal(5, manager:getLocalSettingValue("settings/rv_plugin:a.b", caches))
    assert.are.equal(9, manager:getLocalSettingValue("defaults:RV_DEFAULT", caches))
  end)

  it("getLocalSettingValue returns nil for a key without a domain, an unknown domain or a missing settings file", function()
    local caches = {}
    assert.is_nil(manager:getLocalSettingValue("no_colon", caches))
    assert.is_nil(manager:getLocalSettingValue("unknown:thing", caches))
    assert.is_nil(manager:getLocalSettingValue("settings/does_not_exist:a", caches))
  end)

  it("_writeLocalSettingValue sets a nested reader setting and keeps its siblings", function()
    G_reader_settings:save("rv_nest", { keep = 1, sub = { old = true } })
    local before = G_reader_settings:read("rv_nest")

    finally(function()
      G_reader_settings:delete("rv_nest")
    end)

    local ok = manager:_writeLocalSettingValue("reader:rv_nest.sub.new", 42)
    assert.is_true(ok)

    local after = G_reader_settings:read("rv_nest")
    assert.are.equal(42, after.sub.new)
    assert.are.equal(1, after.keep)
    assert.is_true(after.sub.old)

    assert.is_nil(before.sub.new)

    local on_disk = dofile(test_data_dir .. "/settings.reader.lua")
    assert.are.equal(42, on_disk.rv_nest.sub.new)
  end)

  it("_writeLocalSettingValue writes plugin settings and defaults to their files and rejects a key without a domain", function()
    finally(function()
      os.remove(DataStorage:getSettingsDir() .. "/rv_plugin2.lua")
      os.remove(test_data_dir .. "/defaults.custom.lua")
    end)

    assert.is_true(manager:_writeLocalSettingValue("settings/rv_plugin2:x.y", "z"))
    local p_s = LuaSettings:open(DataStorage:getSettingsDir() .. "/rv_plugin2.lua")
    assert.are.equal("z", p_s:read("x").y)

    assert.is_true(manager:_writeLocalSettingValue("defaults:RV_DEFAULT2", 3))
    local d_s = LuaSettings:open(test_data_dir .. "/defaults.custom.lua")
    assert.are.equal(3, d_s:read("RV_DEFAULT2"))

    assert.is_false(manager:_writeLocalSettingValue("no_colon", 1))
  end)

  it("writing a leaf that restores a table default leaves no partial table in defaults.custom.lua", function()
    local custom_file = test_data_dir .. "/defaults.custom.lua"
    finally(function()
      os.remove(custom_file)
    end)

    G_defaults:save("DTAP_ZONE_MENU", { x = 0.1, y = 0, w = 1, h = 1 / 8 })
    G_defaults:flush()

    assert.is_true(manager:_writeLocalSettingValue("defaults:DTAP_ZONE_MENU.x", 0))

    assert.is_nil(LuaSettings:open(custom_file):read("DTAP_ZONE_MENU"))

    assert.are.same(
      { x = 0, y = 0, w = 1, h = 1 / 8 },
      require("luadefaults"):open(custom_file):read("DTAP_ZONE_MENU")
    )
  end)

  it("an imported defaults setting is still there after the next settings comparison", function()
    local old = _G.G_defaults
    _G.G_defaults = require("luadefaults"):open()

    local old_show = UIManager.show
    finally(function()
      UIManager.show = old_show
      _G.G_defaults = old
      os.remove(test_data_dir .. "/defaults.custom.lua")
    end)

    local shown_menu
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    menus.show_differing_settings_menu(sync_instance, "Other", { ["defaults:DCREREADER_CONFIG_DEFAULT_FONT_SIZE"] = 31 }, nil)
    assert.is_not_nil(shown_menu)
    shown_menu.item_table[1].callback()

    local val = manager:getLocalSettingValue("defaults:DCREREADER_CONFIG_DEFAULT_FONT_SIZE", {})
    assert.are.equal(31, val)
  end)

  it("an imported defaults setting takes effect in G_defaults", function()
    local old = _G.G_defaults
    _G.G_defaults = require("luadefaults"):open()

    local old_show = UIManager.show
    finally(function()
      UIManager.show = old_show
      _G.G_defaults = old
      os.remove(test_data_dir .. "/defaults.custom.lua")
    end)

    local shown_menu
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    menus.show_differing_settings_menu(sync_instance, "Other", { ["defaults:DCREREADER_CONFIG_DEFAULT_FONT_SIZE"] = 31 }, nil)
    assert.is_not_nil(shown_menu)
    shown_menu.item_table[1].callback()

    assert.are.equal(31, _G.G_defaults:read("DCREREADER_CONFIG_DEFAULT_FONT_SIZE"))
  end)

  it("the pull menu imports only the checked settings and closes", function()
    local msg_shown
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      msg_shown = m
    end

    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    local closed_widget
    local old_close = UIManager.close
    UIManager.close = function(ui_mgr, widget)
      closed_widget = widget
      old_close(ui_mgr, widget)
    end

    finally(function()
      utils.show_msg = old_msg
      UIManager.show = old_show
      UIManager.close = old_close
      G_reader_settings:delete("rv_a")
      G_reader_settings:delete("rv_b")
    end)

    menus.show_differing_settings_menu(sync_instance, "Other", { ["reader:rv_a"] = 1, ["reader:rv_b"] = 2 }, nil)
    assert.is_not_nil(shown_menu)

    shown_menu.item_table[5].callback()
    shown_menu.item_table[1].callback()

    assert.are.equal(1, G_reader_settings:read("rv_a"))
    assert.is_nil(G_reader_settings:read("rv_b"))
    assert.is_truthy(msg_shown and msg_shown:find("1"))
    assert.are.equal(shown_menu, closed_widget)
  end)

  it("the import message uses the singular for one setting", function()
    local msg_shown
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      msg_shown = m
    end

    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    finally(function()
      utils.show_msg = old_msg
      UIManager.show = old_show
      G_reader_settings:delete("rv_single")
    end)

    menus.show_differing_settings_menu(sync_instance, "Other", { ["reader:rv_single"] = 10 }, nil)
    assert.is_not_nil(shown_menu)
    shown_menu.item_table[1].callback()

    assert.are.equal("Successfully imported 1 setting.", msg_shown)
  end)

  it("Import after Clear Selection imports nothing and says so", function()
    local msg_shown
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      msg_shown = m
    end

    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    local closed_widget
    local old_close = UIManager.close
    UIManager.close = function(ui_mgr, widget)
      closed_widget = widget
      old_close(ui_mgr, widget)
    end

    finally(function()
      utils.show_msg = old_msg
      UIManager.show = old_show
      UIManager.close = old_close
      G_reader_settings:delete("rv_c1")
      G_reader_settings:delete("rv_c2")
    end)

    menus.show_differing_settings_menu(sync_instance, "Other", { ["reader:rv_c1"] = 1, ["reader:rv_c2"] = 2 }, nil)
    assert.is_not_nil(shown_menu)

    shown_menu.item_table[3].callback()
    shown_menu.item_table[1].callback()

    assert.are.equal("No settings imported.", msg_shown)
    assert.is_nil(G_reader_settings:read("rv_c1"))
    assert.is_nil(G_reader_settings:read("rv_c2"))
    assert.are.equal(shown_menu, closed_widget)
  end)

  it("the devices list shows the other devices sorted by name with their push time", function()
    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    finally(function()
      UIManager.show = old_show
    end)

    local my_dev = manager:getDeviceName()
    menus.show_devices_menu(sync_instance, {
      Zed = { timestamp = "2026-01-02 03:04:05", settings = {} },
      Alpha = { settings = {} },
      [my_dev] = { timestamp = "x", settings = {} },
    })

    assert.is_not_nil(shown_menu)
    assert.are.equal(2, #shown_menu.item_table)
    assert.are.equal("Alpha (unknown)", shown_menu.item_table[1].text)
    assert.are.equal("Zed (2026-01-02 03:04:05)", shown_menu.item_table[2].text)
  end)

  it("pushSettings with nothing selected says so and uploads nothing", function()
    local msg_shown
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      msg_shown = m
    end

    local sync_calls = 0
    local old_sync = SyncService.sync
    SyncService.sync = function()
      sync_calls = sync_calls + 1
    end

    finally(function()
      utils.show_msg = old_msg
      SyncService.sync = old_sync
    end)

    sync_instance.settings.selected_settings = {}
    manager:pushSettings()

    assert.are.equal(
      "No settings are selected. Please select settings to sync in 'Show changed settings'.",
      msg_shown
    )
    assert.are.equal(0, sync_calls)
  end)

  it("defaults selected_settings to an empty table on init if older settings table lacked it", function()
    local _meta = require("plugins/AnnotationSync.koplugin/_meta")
    G_reader_settings:save(_meta.plugin_id, {
      sync_server = { url = "http://mock", type = "webdav" },
      device_name = "test_dev",
    })
    G_reader_settings:flush()

    local dummy_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local plugin = AnnotationSyncPlugin:new({
      ui = dummy_ui,
      plugin_id = _meta.plugin_id,
      path = "plugins/AnnotationSync.koplugin",
    })
    plugin:init()

    assert.is_not_nil(plugin.settings.selected_settings)
    assert.are.same({}, plugin.settings.selected_settings)

    local msg_shown
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      msg_shown = m
    end
    finally(function()
      utils.show_msg = old_msg
    end)

    plugin.manager:pushSettings()
    assert.are.equal(
      "No settings are selected. Please select settings to sync in 'Show changed settings'.",
      msg_shown
    )
  end)

  it("with an empty selection, getSelectedSettingsWithValues returns nil without calling build_tree", function()
    local SettingsSelection = require("plugins/AnnotationSync.koplugin/settings_selection")
    local build_tree_calls = 0
    local old_build_tree = SettingsSelection.build_tree
    SettingsSelection.build_tree = function(...)
      build_tree_calls = build_tree_calls + 1
      return old_build_tree(...)
    end
    finally(function()
      SettingsSelection.build_tree = old_build_tree
    end)

    sync_instance.settings.selected_settings = {}
    local result = manager:getSelectedSettingsWithValues()

    assert.is_nil(result)
    assert.are.equal(0, build_tree_calls)
  end)

  it("pushSettings files the settings under the device name, or the model when the name is empty", function()
    local pushed_data
    local old_push = remote.push_settings
    remote.push_settings = function(_, json_path, on_complete)
      pushed_data = utils.read_json(json_path)
      on_complete(true)
    end

    G_reader_settings:save("rv_push", 5)
    sync_instance.settings.selected_settings = { ["reader:rv_push"] = true }

    finally(function()
      remote.push_settings = old_push
      G_reader_settings:delete("rv_push")
      sync_instance.settings.selected_settings = {}
      sync_instance.settings.device_name = ""
    end)

    sync_instance.settings.device_name = "Kobo A"
    manager:pushSettings()
    assert.is_not_nil(pushed_data)
    assert.is_not_nil(pushed_data["Kobo A"])
    assert.are.equal(5, pushed_data["Kobo A"].settings["reader:rv_push"])
    assert.is_not_nil(pushed_data["Kobo A"].timestamp)

    pushed_data = nil
    sync_instance.settings.device_name = ""
    manager:pushSettings()
    local model_name = require("device").model or "unknown"
    assert.is_not_nil(pushed_data)
    assert.is_not_nil(pushed_data[model_name])
    assert.are.equal(5, pushed_data[model_name].settings["reader:rv_push"])
  end)

  it("a failed pull says so", function()
    local msgs = {}
    local old_msg = utils.show_msg
    utils.show_msg = function(m)
      table.insert(msgs, m)
    end

    local shown_menu
    local old_show = UIManager.show
    UIManager.show = function(ui_mgr, widget)
      if widget and widget.item_table then
        shown_menu = widget
      else
        old_show(ui_mgr, widget)
      end
    end

    local old_pull = remote.pull_settings
    remote.pull_settings = function(_, _, cb)
      cb(false)
    end

    finally(function()
      utils.show_msg = old_msg
      UIManager.show = old_show
      remote.pull_settings = old_pull
    end)

    manager:pullSettings()

    assert.are.equal("Fetching settings from cloud...", msgs[1])
    assert.are.equal("Failed to fetch settings from cloud", msgs[2])
    assert.is_nil(shown_menu)
  end)

  it("a pull without a cloud settings file says there are no other devices", function()
    local msgs = {}
    local old_msg = utils.show_msg
    local old_sync = SyncService.sync
    finally(function()
      utils.show_msg = old_msg
      SyncService.sync = old_sync
    end)

    utils.show_msg = function(m)
      table.insert(msgs, m)
    end

    SyncService.sync = function(_, path, sync_cb, _, finish_cb)
      local cb_res = sync_cb(path, path .. ".sync", path .. ".income", 404)
      if finish_cb then
        finish_cb(cb_res)
      end
    end

    manager:pullSettings()

    assert.is_truthy(util.arrayContains(msgs, "No other devices found in cloud settings."))
  end)
end)
