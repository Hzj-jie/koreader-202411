describe("AnnotationSync pending queue", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util, utils, Notification, menus
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_pending_queue_tmp"
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
    Notification = require("ui/widget/notification")
    menus = require("plugins/AnnotationSync.koplugin/menus")
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
    package.loaded["plugins/AnnotationSync.koplugin/menus"] = nil
  end)

  before_each(function()
    os.remove(manager:changedDocumentsFile())
  end)

  it("Sync current book now moves the book to the front of the pending books", function()
    local path_a = test_data_dir .. "/A.epub"
    local path_b = test_data_dir .. "/B.epub"
    local path_c = test_data_dir .. "/C.epub"

    manager:_writeChangedDocumentsFile({ path_a, path_b, path_c })
    manager.running = true

    local toast_msg
    local orig_notify = Notification.notify
    Notification.notify = function(self_notif, text)
      toast_msg = text
    end

    finally(function()
      manager.running = nil
      manager.requested = {}
      Notification.notify = orig_notify
    end)

    manager:syncNow(path_c)

    local _, list = manager:getPendingChangedDocuments()
    assert.are.equal(3, #list)
    assert.are.equal(path_c, list[1])
    assert.are.equal(path_a, list[2])
    assert.are.equal(path_b, list[3])

    assert.are.equal("Manual Sync", manager.requested[path_c])
    assert.are.equal("Syncing in the background: C.epub", toast_msg)
  end)

  it("Sync current book now on a book that isn't pending adds it at the front", function()
    local path_a = test_data_dir .. "/A.epub"
    local path_b = test_data_dir .. "/B.epub"
    local path_d = test_data_dir .. "/D.epub"

    manager:_writeChangedDocumentsFile({ path_a, path_b })
    manager.running = true

    local orig_notify = Notification.notify
    Notification.notify = function() end

    finally(function()
      manager.running = nil
      manager.requested = {}
      Notification.notify = orig_notify
    end)

    manager:syncNow(path_d)

    local _, list = manager:getPendingChangedDocuments()
    assert.are.equal(3, #list)
    assert.are.equal(path_d, list[1])
    assert.are.equal(path_a, list[2])
    assert.are.equal(path_b, list[3])
  end)

  it("Sync all pending books with nothing pending says so and requests nothing", function()
    manager:_writeChangedDocumentsFile({})
    manager.running = true

    local captured_msg
    local orig_show_msg = utils.show_msg
    utils.show_msg = function(msg)
      captured_msg = msg
    end

    local toast_called = false
    local orig_notify = Notification.notify
    Notification.notify = function()
      toast_called = true
    end

    finally(function()
      manager.running = nil
      manager.requested = {}
      utils.show_msg = orig_show_msg
      Notification.notify = orig_notify
    end)

    manager:syncAllChangedDocuments()

    assert.are.equal("No pending books.", captured_msg)
    assert.is_nil(next(manager.requested))
    assert.is_false(toast_called)
  end)

  it("Show pending books with nothing pending says so instead of opening an empty list", function()
    manager:_writeChangedDocumentsFile({})

    local captured_msg
    local orig_show_msg = utils.show_msg
    utils.show_msg = function(msg)
      captured_msg = msg
    end

    local shown_widgets = {}
    local orig_show = UIManager.show
    UIManager.show = function(ui_mgr, widget, ...)
      table.insert(shown_widgets, widget)
      return orig_show(ui_mgr, widget, ...)
    end

    finally(function()
      utils.show_msg = orig_show_msg
      UIManager.show = orig_show
      for _, w in ipairs(shown_widgets) do
        UIManager:closeIfShown(w)
      end
    end)

    menus.show_pending_documents(sync_instance)

    assert.are.equal("No pending books.", captured_msg)
    assert.are.equal(0, #shown_widgets)
  end)

  it("Show pending books sorts the books by file name, ignoring case and folders", function()
    local files = { "/z/b.epub", "/a/C.epub", "/m/a.epub" }
    manager:_writeChangedDocumentsFile(files)

    local shown_widgets = {}
    local orig_show = UIManager.show
    UIManager.show = function(ui_mgr, widget, ...)
      table.insert(shown_widgets, widget)
      return orig_show(ui_mgr, widget, ...)
    end

    finally(function()
      UIManager.show = orig_show
      for _, w in ipairs(shown_widgets) do
        UIManager:closeIfShown(w)
      end
    end)

    menus.show_pending_documents(sync_instance)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)
    assert.are.equal(3, #menu.item_table)
    assert.are.equal("a.epub", menu.item_table[1].text)
    assert.are.equal("b.epub", menu.item_table[2].text)
    assert.are.equal("C.epub", menu.item_table[3].text)
  end)
end)
