describe("AnnotationSync setting keys with dots", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, LuaSettings, DataStorage
  local remote, utils, menus
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_dotted_setting_keys_tmp"
  local old_getDataDir
  local settings_dir

  local HAMLET = "/books/Hamlet.epub"
  local ENCODED = "/books/My%20Book.epub"

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
    remote = require("plugins/AnnotationSync.koplugin/remote")
    utils = require("plugins/AnnotationSync.koplugin/utils")
    menus = require("plugins/AnnotationSync.koplugin/menus")
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

  local function open_shortcut_leaves(shown)
    local bs_path = settings_dir .. "/bookshortcuts.lua"
    local s = LuaSettings:open(bs_path)
    s:save(HAMLET, true)
    s:save(ENCODED, true)
    s:flush()

    local old_show = UIManager.show
    UIManager.show = function(self, widget)
      table.insert(shown, widget)
      return old_show(self, widget)
    end

    sync_instance:showChangedSettings()

    local root_menu = shown[#shown]
    for _, item in ipairs(root_menu.item_table) do
      local text = item.text or (item.text_func and item.text_func()) or ""
      if text:find("[settings/bookshortcuts] bookshortcuts >", 1, true) then
        item.callback()
        break
      end
    end

    local leaves_menu = shown[#shown]
    local leaves = {}
    for _, item in ipairs(leaves_menu.item_table) do
      if item.setting_id and item.text_func then
        local text = item.text_func()
        if text:find(HAMLET, 1, true) then
          leaves[HAMLET] = item
        elseif text:find(ENCODED, 1, true) then
          leaves[ENCODED] = item
        end
      end
    end
    return leaves
  end

  it("book shortcuts to files are pushed with their values", function()
    local shown = {}
    local bs_path = settings_dir .. "/bookshortcuts.lua"
    local old_show = UIManager.show
    local old_push_settings = remote.push_settings
    finally(function()
      UIManager.show = old_show
      for _, w in ipairs(shown) do
        if UIManager:isWindowWidget(w) then
          UIManager:close(w)
        end
      end
      remote.push_settings = old_push_settings
      sync_instance.settings.selected_settings = {}
      os.remove(bs_path)
    end)

    local leaves = open_shortcut_leaves(shown)
    leaves[HAMLET].callback()
    leaves[ENCODED].callback()

    local pushed
    remote.push_settings = function(plugin, json_path, on_complete)
      pushed = utils.read_json(json_path)
      on_complete(true)
    end

    manager:pushSettings()

    local settings = pushed[manager:getDeviceName()].settings
    assert.is_true(settings[leaves[HAMLET].setting_id])
    assert.is_true(settings[leaves[ENCODED].setting_id])
  end)

  it("book shortcuts to files pulled from another device are imported as the same keys", function()
    local shown = {}
    local bs_path = settings_dir .. "/bookshortcuts.lua"
    local old_show = UIManager.show
    finally(function()
      UIManager.show = old_show
      for _, w in ipairs(shown) do
        if UIManager:isWindowWidget(w) then
          UIManager:close(w)
        end
      end
      os.remove(bs_path)
    end)

    local leaves = open_shortcut_leaves(shown)
    local hamlet_id = leaves[HAMLET].setting_id
    local encoded_id = leaves[ENCODED].setting_id

    for _, w in ipairs(shown) do
      if UIManager:isWindowWidget(w) then
        UIManager:close(w)
      end
    end
    os.remove(bs_path)

    menus.show_differing_settings_menu(sync_instance, "Other", { [hamlet_id] = true, [encoded_id] = true }, nil)
    local diff_menu = shown[#shown]
    assert.truthy(diff_menu)

    local all_text = ""
    for _, item in ipairs(diff_menu.item_table) do
      local text = item.text or (item.text_func and item.text_func()) or ""
      all_text = all_text .. "\n" .. text
    end
    assert.truthy(all_text:find(HAMLET, 1, true))
    assert.truthy(all_text:find(ENCODED, 1, true))

    diff_menu.item_table[1].callback()

    local s = LuaSettings:open(bs_path)
    assert.is_true(s:read(HAMLET))
    assert.is_true(s:read(ENCODED))
  end)
end)
