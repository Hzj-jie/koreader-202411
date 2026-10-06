describe("AnnotationSync Settings Persistence", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_settings_persistence_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    json = require("json")
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
    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    UIManager:show(readerui)
    fastforward_ui_events()
  end)

  after_each(function()
    if readerui then
      readerui:onClose()
    end
    G_reader_settings:delete(sync_instance.plugin_id)
    G_reader_settings:delete("cloud_server_object")
    G_reader_settings:delete("cloud_download_dir")
    G_reader_settings:delete("cloud_provider_type")
  end)

  it("should use default settings if absent", function()
    -- 1. Delete settings
    G_reader_settings:delete(sync_instance.plugin_id)

    -- 2. Re-initialize plugin
    sync_instance:init()

    -- 3. Verify defaults
    assert.is_false(sync_instance.settings.use_filename)
    assert.is_false(sync_instance.settings.network_auto_sync)
  end)

  it("should migrate legacy cloud_server_object on init", function()
    -- 1. Setup legacy setting
    local legacy_server = { url = "http://legacy-server", type = "webdav" }
    G_reader_settings:save("cloud_server_object", json.encode(legacy_server))

    -- 2. Clear plugin settings sync_server
    local plugin_settings = G_reader_settings:read(sync_instance.plugin_id)
      or {}
    plugin_settings.sync_server = nil
    G_reader_settings:save(sync_instance.plugin_id, plugin_settings)

    -- 3. Re-initialize plugin
    sync_instance:init()

    -- 4. Verify it was migrated
    assert.is_not_nil(sync_instance.settings.sync_server)
    assert.is_equal(
      "http://legacy-server",
      sync_instance.settings.sync_server.url
    )
    assert.is_equal("webdav", sync_instance.settings.sync_server.type)
  end)

  it(
    "should save sync_server and update G_reader_settings on confirmation",
    function()
      local test_server =
        { url = "http://test-server-confirm", type = "dropbox" }

      -- 1. Call onSyncServiceConfirm
      sync_instance:onSyncServiceConfirm(test_server)

      -- 2. Verify sync_server is updated in settings
      assert.is_not_nil(sync_instance.settings.sync_server)
      assert.is_equal(
        "http://test-server-confirm",
        sync_instance.settings.sync_server.url
      )

      -- 3. Verify G_reader_settings keys are updated for compatibility
      local server_json = G_reader_settings:read("cloud_server_object")
      assert.is_not_nil(server_json)
      local saved_server = json.decode(server_json)
      assert.is_equal("http://test-server-confirm", saved_server.url)
      assert.is_equal(
        "http://test-server-confirm",
        G_reader_settings:read("cloud_download_dir")
      )
      assert.is_equal("dropbox", G_reader_settings:read("cloud_provider_type"))
    end
  )

  it("should show current cloud in the settings menu", function()
    -- 1. Verify default displays "None"
    local menu_items = {}
    sync_instance:addToMainMenu(menu_items)
    local settings_menu = menu_items.annotation_sync_plugin.sub_item_table[1]
    local last_item =
      settings_menu.sub_item_table[#settings_menu.sub_item_table]

    assert.is_not_nil(last_item)
    assert.is_false(last_item.enabled)
    assert.is_not_nil(last_item.text_func)
    assert.is_equal("Current cloud: None", last_item.text_func())

    -- 2. Mock sync_server and verify it updates dynamically
    sync_instance.settings.sync_server =
      { url = "https://my-test-cloud.example.com", type = "webdav" }
    assert.is_equal(
      "Current cloud: https://my-test-cloud.example.com",
      last_item.text_func()
    )
  end)

  it("should open SyncService dialog from Cloud settings menu", function()
    -- 1. Mock UIManager:show to intercept SyncService instance
    local opened_syncservice = false
    local captured_widget = nil
    local old_show = UIManager.show
    finally(function()
      UIManager.show = old_show
    end)
    UIManager.show = function(this, widget)
      if widget.generateItemTable and widget.title == "Cloud sync settings" then
        opened_syncservice = true
        captured_widget = widget
        return
      end
      return old_show(this, widget)
    end

    -- 2. Generate menu items
    local menu_items = {}
    sync_instance:addToMainMenu(menu_items)
    local settings_menu = menu_items.annotation_sync_plugin.sub_item_table[1]

    local cloud_settings_item
    for _, item in ipairs(settings_menu.sub_item_table) do
      if item.text == "Cloud settings" then
        cloud_settings_item = item
        break
      end
    end
    assert.is_not_nil(cloud_settings_item)

    -- 3. Trigger callback and verify SyncService dialog is shown
    cloud_settings_item.callback()
    assert.is_true(opened_syncservice)
    assert.is_not_nil(captured_widget)

    -- 4. Verify onConfirm triggers onSyncServiceConfirm
    local test_server =
      { url = "http://test-server-cloud-settings", type = "dropbox" }
    captured_widget.onConfirm(test_server)
    assert.is_not_nil(sync_instance.settings.sync_server)
    assert.is_equal(
      "http://test-server-cloud-settings",
      sync_instance.settings.sync_server.url
    )
  end)
end)
