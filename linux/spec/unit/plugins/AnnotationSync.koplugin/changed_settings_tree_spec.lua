describe("AnnotationSync changed settings tree", function()
  local UIManager, AnnotationSyncPlugin, test_utils, DataStorage, LuaSettings, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_changed_settings_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    DataStorage = require("datastorage")
    LuaSettings = require("luasettings")
    util = require("util")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    sync_instance.path = "plugins/AnnotationSync.koplugin"
  end)

  teardown(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
  end)

  local function open_tree()
    local shown_menus = {}
    local orig_show = UIManager.show
    UIManager.show = function(ui_mgr, widget, ...)
      table.insert(shown_menus, widget)
      return orig_show(ui_mgr, widget, ...)
    end

    sync_instance:showChangedSettings()

    local root_menu = shown_menus[#shown_menus]
    local cleanup = function()
      UIManager.show = orig_show
      for _, w in ipairs(shown_menus) do
        UIManager:closeIfShown(w)
      end
    end

    return root_menu, shown_menus, cleanup
  end

  it("never lists excluded reader settings, even when they changed", function()
    local old_lastfile = G_reader_settings:read("lastfile")
    local old_cloud = G_reader_settings:read("cloud_download_dir")
    local old_dev_id = G_reader_settings:read("device_id")

    G_reader_settings:save("lastfile", "/x/y.epub")
    G_reader_settings:save("cloud_download_dir", "http://somewhere")
    G_reader_settings:save("device_id", "abc")

    local root_menu, _, cleanup = open_tree()
    finally(function()
      cleanup()
      if old_lastfile then
        G_reader_settings:save("lastfile", old_lastfile)
      else
        G_reader_settings:delete("lastfile")
      end
      if old_cloud then
        G_reader_settings:save("cloud_download_dir", old_cloud)
      else
        G_reader_settings:delete("cloud_download_dir")
      end
      if old_dev_id then
        G_reader_settings:save("device_id", old_dev_id)
      else
        G_reader_settings:delete("device_id")
      end
    end)

    assert.is_not_nil(root_menu)
    for _, item in ipairs(root_menu.item_table) do
      assert.is_not_equal("reader:lastfile", item.setting_id)
      assert.is_not_equal("reader:cloud_download_dir", item.setting_id)
      assert.is_not_equal("reader:device_id", item.setting_id)

      local txt = item.text or (item.text_func and item.text_func()) or ""
      assert.is_nil(txt:find("lastfile", 1, true))
      assert.is_nil(txt:find("cloud_download_dir", 1, true))
      assert.is_nil(txt:find("device_id", 1, true))
    end
  end)

  it("never lists a setting nested under an excluded key", function()
    local old_fonts = G_reader_settings:read("cre_font_family_fonts")
    G_reader_settings:save("cre_font_family_fonts", { serif = "X" })

    local root_menu, _, cleanup = open_tree()
    finally(function()
      cleanup()
      if old_fonts then
        G_reader_settings:save("cre_font_family_fonts", old_fonts)
      else
        G_reader_settings:delete("cre_font_family_fonts")
      end
    end)

    assert.is_not_nil(root_menu)
    for _, item in ipairs(root_menu.item_table) do
      if item.setting_id then
        assert.is_nil(item.setting_id:find("cre_font_family_fonts", 1, true))
      end
      local txt = item.text or (item.text_func and item.text_func()) or ""
      assert.is_nil(txt:find("cre_font_family_fonts", 1, true))
    end
  end)

  it("lists a changed list setting as one item with its whole value", function()
    G_reader_settings:save("rv_list", { "a", "b" })

    local root_menu, _, cleanup = open_tree()
    finally(function()
      cleanup()
      G_reader_settings:delete("rv_list")
    end)

    assert.is_not_nil(root_menu)
    local found_item
    for _, item in ipairs(root_menu.item_table) do
      if item.setting_id == "reader:rv_list" then
        found_item = item
        break
      end
    end

    assert.is_not_nil(found_item)
    local txt = found_item.text_func and found_item.text_func() or ""
    assert.is_truthy(txt:find("nil -> [a, b]", 1, true))
  end)

  it("groups a changed plugin settings file under its own branch and skips excluded files", function()
    local bookshortcuts_file = DataStorage:getSettingsDir() .. "/bookshortcuts.lua"
    local cloudstorage_file = DataStorage:getSettingsDir() .. "/cloudstorage.lua"

    local bs_settings = LuaSettings:open(bookshortcuts_file)
    bs_settings:save("settings", { directory_action = "Reader" })
    bs_settings:flush()

    local cs_settings = LuaSettings:open(cloudstorage_file)
    cs_settings:save("cs_servers", { { name = "x" } })
    cs_settings:flush()

    local root_menu, shown_menus, cleanup = open_tree()
    finally(function()
      cleanup()
      os.remove(bookshortcuts_file)
      os.remove(cloudstorage_file)
    end)

    assert.is_not_nil(root_menu)

    local bs_branch_item
    for _, item in ipairs(root_menu.item_table) do
      local txt = item.text or (item.text_func and item.text_func()) or ""
      if txt:find("[settings/bookshortcuts] bookshortcuts >", 1, true) then
        bs_branch_item = item
      end
      assert.is_nil(txt:find("settings/cloudstorage", 1, true))
      if item.setting_id then
        assert.is_nil(item.setting_id:find("cloudstorage", 1, true))
      end
    end
    assert.is_not_nil(bs_branch_item)

    -- Open bookshortcuts branch
    bs_branch_item.callback()
    local bs_menu = shown_menus[#shown_menus]
    assert.is_not_nil(bs_menu)

    local settings_branch_item
    for _, item in ipairs(bs_menu.item_table) do
      local txt = item.text or (item.text_func and item.text_func()) or ""
      if txt:find("settings >", 1, true) then
        settings_branch_item = item
        break
      end
    end
    assert.is_not_nil(settings_branch_item)

    -- Open settings branch under bookshortcuts
    settings_branch_item.callback()
    local leaf_menu = shown_menus[#shown_menus]
    assert.is_not_nil(leaf_menu)

    local leaf_item
    for _, item in ipairs(leaf_menu.item_table) do
      if item.setting_id == "settings/bookshortcuts:settings.directory_action" then
        leaf_item = item
        break
      end
    end
    assert.is_not_nil(leaf_item)
    local leaf_txt = leaf_item.text_func and leaf_item.text_func() or ""
    assert.is_truthy(leaf_txt:find("FM -> Reader", 1, true))
  end)

  it("Select All and Clear Selection on a branch affect only the settings under it", function()
    G_reader_settings:save("rv_branch", { one = 1, two = 2 })
    G_reader_settings:save("rv_other", 5)

    local root_menu, shown_menus, cleanup = open_tree()
    finally(function()
      cleanup()
      G_reader_settings:delete("rv_branch")
      G_reader_settings:delete("rv_other")
      sync_instance.settings.selected_settings = {}
      sync_instance:saveSettings()
    end)

    assert.is_not_nil(root_menu)

    local branch_item
    for _, item in ipairs(root_menu.item_table) do
      local txt = item.text or (item.text_func and item.text_func()) or ""
      if txt:find("[reader] rv_branch >", 1, true) then
        branch_item = item
        break
      end
    end
    assert.is_not_nil(branch_item)

    branch_item.callback()
    local branch_menu = shown_menus[#shown_menus]
    assert.is_not_nil(branch_menu)

    -- 1. Tap Select All (item 1)
    branch_menu.item_table[1].callback()
    assert.is_true(sync_instance.settings.selected_settings["reader:rv_branch.one"])
    assert.is_true(sync_instance.settings.selected_settings["reader:rv_branch.two"])
    assert.is_nil(sync_instance.settings.selected_settings["reader:rv_other"])

    -- 2. Tap Clear Selection (item 2)
    branch_menu.item_table[2].callback()
    assert.is_nil(sync_instance.settings.selected_settings["reader:rv_branch.one"])
    assert.is_nil(sync_instance.settings.selected_settings["reader:rv_branch.two"])
  end)

  it("does not list a setting this device never set", function()
    G_reader_settings:delete("auto_standby_timeout_seconds")
    G_reader_settings:flush()

    local root_menu, _, cleanup = open_tree()
    finally(cleanup)

    assert.is_not_nil(root_menu)
    for _, item in ipairs(root_menu.item_table) do
      assert.is_not_equal("reader:auto_standby_timeout_seconds", item.setting_id)
    end
  end)
end)
