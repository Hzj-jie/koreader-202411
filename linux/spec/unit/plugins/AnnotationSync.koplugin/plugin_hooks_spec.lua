describe("AnnotationSync plugin hooks and wiring", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util, utils, Device, Dispatcher
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_plugin_hooks_tmp"
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
    utils = require("plugins/AnnotationSync.koplugin/utils")
    Device = require("device")
    Dispatcher = require("dispatcher")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)

    G_reader_settings:save("cloud_download_dir", "http://mock")
    G_reader_settings:save("cloud_server_object", json.encode({ url = "http://mock", type = "webdav" }))

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
    manager = sync_instance.manager
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
    os.remove(manager:changedDocumentsFile())
    sync_instance.settings.network_auto_sync = false
  end)

  it("init moves the old annotation_sync_use_filename setting into the plugin settings", function()
    G_reader_settings:save("annotation_sync_use_filename", true)
    sync_instance.settings.use_filename = false

    local orig_register = readerui.menu.registerToMainMenu
    readerui.menu.registerToMainMenu = function() end
    finally(function()
      readerui.menu.registerToMainMenu = orig_register
      sync_instance.settings.use_filename = false
      sync_instance:saveSettings()
      G_reader_settings:delete("annotation_sync_use_filename")
    end)

    sync_instance:init()

    assert.is_true(sync_instance.settings.use_filename)
    assert.is_false(G_reader_settings:has("annotation_sync_use_filename"))
  end)

  it("registers the plugin into readerui exactly once", function()
    local count = 0
    for _, child in ipairs(readerui) do
      if child == sync_instance then
        count = count + 1
      end
    end
    assert.are.equal(1, count)
  end)

  it("an annotation change marks the open book as pending", function()
    sync_instance:onAnnotationsModified({ { text = "x" } })

    local _, docs = manager:getPendingChangedDocuments()
    assert.are.equal(1, #docs)
    assert.are.equal(readerui.document.file, docs[1])
  end)

  it("an annotation change made while synced annotations are applied is ignored", function()
    sync_instance.is_applying_sync = true
    finally(function()
      sync_instance.is_applying_sync = false
    end)

    sync_instance:onAnnotationsModified({ { text = "x" } })

    assert.are.equal(0, manager:getPendingChangedDocuments())
  end)

  it("every gesture action is registered with a handler that calls the plugin", function()
    local actions = {}
    local orig_registerAction = Dispatcher.registerAction
    Dispatcher.registerAction = function(self_disp, name, def)
      actions[name] = def
    end

    local orig_push = manager.pushSettings
    local orig_pull = manager.pullSettings
    local orig_sync_all = manager.syncAllChangedDocuments
    local orig_manual = sync_instance.manualSync

    local called_push = 0
    local called_pull = 0
    local called_sync_all = 0
    local called_manual = 0

    manager.pushSettings = function()
      called_push = called_push + 1
    end
    manager.pullSettings = function()
      called_pull = called_pull + 1
    end
    manager.syncAllChangedDocuments = function()
      called_sync_all = called_sync_all + 1
    end
    sync_instance.manualSync = function()
      called_manual = called_manual + 1
    end

    finally(function()
      Dispatcher.registerAction = orig_registerAction
      manager.pushSettings = orig_push
      manager.pullSettings = orig_pull
      manager.syncAllChangedDocuments = orig_sync_all
      sync_instance.manualSync = orig_manual
    end)

    sync_instance:onDispatcherRegisterActions()

    assert.is_not_nil(actions.annotation_sync_manual_sync)
    assert.are.equal("AnnotationSyncManualSync", actions.annotation_sync_manual_sync.event)
    assert.is_true(actions.annotation_sync_manual_sync.reader)

    assert.is_not_nil(actions.annotation_sync_push_settings)
    assert.are.equal("AnnotationSyncPushSettings", actions.annotation_sync_push_settings.event)
    assert.is_true(actions.annotation_sync_push_settings.general)

    assert.is_not_nil(actions.annotation_sync_pull_settings)
    assert.are.equal("AnnotationSyncPullSettings", actions.annotation_sync_pull_settings.event)
    assert.is_true(actions.annotation_sync_pull_settings.general)

    assert.is_not_nil(actions.annotation_sync_sync_all)
    assert.are.equal("AnnotationSyncSyncAll", actions.annotation_sync_sync_all.event)
    assert.is_true(actions.annotation_sync_sync_all.general)

    assert.is_function(sync_instance.onAnnotationSyncManualSync)
    assert.is_function(sync_instance.onAnnotationSyncPushSettings)
    assert.is_function(sync_instance.onAnnotationSyncPullSettings)
    assert.is_function(sync_instance.onAnnotationSyncSyncAll)

    assert.is_true(sync_instance:onAnnotationSyncManualSync())
    assert.are.equal(1, called_manual)

    assert.is_true(sync_instance:onAnnotationSyncPushSettings())
    assert.are.equal(1, called_push)

    assert.is_true(sync_instance:onAnnotationSyncPullSettings())
    assert.are.equal(1, called_pull)

    assert.is_true(sync_instance:onAnnotationSyncSyncAll())
    assert.are.equal(1, called_sync_all)
  end)

  it("the device name dialog trims the name and treats the model name as the default", function()
    local InputDialog = require("ui/widget/inputdialog")
    local captured_input
    local orig_new = InputDialog.new
    InputDialog.new = function(self_id, args)
      captured_input = args
      return orig_new(self_id, args)
    end

    local orig_show = UIManager.show
    local shown_widgets = {}
    UIManager.show = function(ui_mgr, widget, ...)
      table.insert(shown_widgets, widget)
      return orig_show(ui_mgr, widget, ...)
    end

    finally(function()
      InputDialog.new = orig_new
      UIManager.show = orig_show
      sync_instance.settings.device_name = ""
      sync_instance:saveSettings()
      for _, w in ipairs(shown_widgets) do
        UIManager:closeIfShown(w)
      end
    end)

    local menu_items = {}
    sync_instance:addToMainMenu(menu_items)
    local sub_items = menu_items.annotation_sync_plugin.sub_item_table[1].sub_item_table

    local device_item
    for _, item in ipairs(sub_items) do
      local txt = item.text_func and item.text_func()
      if txt and txt:find("^Device name:") then
        device_item = item
        break
      end
    end
    assert.is_not_nil(device_item)

    device_item.callback()
    assert.is_not_nil(captured_input)

    local res = captured_input.save_callback("  Kobo Libra  ")
    assert.is_true(res)
    assert.are.equal("Kobo Libra", sync_instance.settings.device_name)
    assert.are.equal("Kobo Libra", manager:getDeviceName())
    assert.are.equal("Device name: Kobo Libra", device_item.text_func())

    local model = Device.model or "unknown"
    res = captured_input.save_callback(model)
    assert.is_true(res)
    assert.are.equal("", sync_instance.settings.device_name)
    assert.are.equal(model, manager:getDeviceName())
  end)

  it("settings push, pull and book sync need a cloud; book sync and Show deleted annotations need an open book", function()
    local menu_items = {}
    sync_instance:addToMainMenu(menu_items)
    local root_items = menu_items.annotation_sync_plugin.sub_item_table

    local push_item, pull_item, sync_curr_item, deleted_item
    for _, item in ipairs(root_items) do
      if item.text == "Push settings to cloud" then
        push_item = item
      elseif item.text == "Pull settings from cloud" then
        pull_item = item
      elseif item.text == "Sync current book now"
        or (item.text_func and item.text_func():find("Sync current book now", 1, true)) then
        sync_curr_item = item
      elseif item.text == "Show deleted annotations" then
        deleted_item = item
      end
    end

    assert.is_not_nil(push_item)
    assert.is_not_nil(pull_item)
    assert.is_not_nil(sync_curr_item)
    assert.is_not_nil(deleted_item)

    local orig_doc = readerui.document
    local orig_sync_server = sync_instance.settings.sync_server
    finally(function()
      readerui.document = orig_doc
      sync_instance.settings.sync_server = orig_sync_server
    end)

    -- 1. With sync_server nil: push, pull, sync current are disabled
    sync_instance.settings.sync_server = nil
    assert.is_false(push_item.enabled_func())
    assert.is_false(pull_item.enabled_func())
    assert.is_false(sync_curr_item.enabled_func())

    -- 2. With sync_server restored and book open: all four are enabled
    sync_instance.settings.sync_server = orig_sync_server
    assert.is_true(push_item.enabled_func())
    assert.is_true(pull_item.enabled_func())
    assert.is_true(sync_curr_item.enabled_func())
    assert.is_true(deleted_item.enabled_func())

    -- 3. With readerui.document = nil: book sync and deleted annotations are disabled
    readerui.document = nil
    assert.is_false(sync_curr_item.enabled_func())
    assert.is_false(deleted_item.enabled_func())

    -- 4. When current book is running: disabled and text shows "Current book is being synchronized"
    readerui.document = orig_doc
    sync_instance.manager.running = orig_doc.file
    assert.are.equal("Current book is being synchronized", sync_curr_item.text_func())
    assert.is_false(sync_curr_item.enabled_func())
    sync_instance.manager.running = nil
    assert.are.equal("Sync current book now", sync_curr_item.text_func())
    assert.is_true(sync_curr_item.enabled_func())
  end)
end)
