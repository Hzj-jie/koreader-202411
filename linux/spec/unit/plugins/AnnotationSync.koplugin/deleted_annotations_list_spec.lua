describe("AnnotationSync deleted annotations list", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util, utils
  local readerui, sync_instance, manager
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_deleted_annotations_tmp"
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
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("cloud_download_dir", "mock")
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
    require("ui/widget/imageviewer").new = _G.old_ImageViewer_new
    UIManager:quit()
    package.loaded["plugins/AnnotationSync.koplugin/main"] = nil
  end)

  before_each(function()
    readerui.annotation.annotations = {}
    os.remove(manager:changedDocumentsFile())
  end)

  local function open_deleted_annotations(tombstones)
    local sync_cache_path = manager:getSyncCachePath(readerui.document.file)
    if tombstones then
      local f = io.open(sync_cache_path, "w")
      if not f then
        error("Could not write " .. sync_cache_path)
      end
      f:write(json.encode(tombstones))
      f:close()
    else
      os.remove(sync_cache_path)
    end

    local shown_widgets = {}
    local orig_show = UIManager.show
    UIManager.show = function(ui_mgr, widget, ...)
      table.insert(shown_widgets, widget)
      return orig_show(ui_mgr, widget, ...)
    end

    local captured_msg
    local orig_show_msg = utils.show_msg
    utils.show_msg = function(msg)
      captured_msg = msg
    end

    sync_instance:showDeletedAnnotations()

    local cleanup = function()
      UIManager.show = orig_show
      utils.show_msg = orig_show_msg
      os.remove(sync_cache_path)
      for _, w in ipairs(shown_widgets) do
        UIManager:closeIfShown(w)
      end
    end

    return shown_widgets, captured_msg, cleanup
  end

  it("says there is nothing to restore when the book has no deleted annotations", function()
    local shown_widgets, captured_msg, cleanup = open_deleted_annotations(nil)
    finally(cleanup)

    assert.are.equal("No deleted annotations found for this document.", captured_msg)
    assert.are.equal(0, #shown_widgets)
  end)

  it("labels an annotation without text or note as Highlight", function()
    local tombstones = {
      {
        page = 1,
        pos0 = "d1",
        pos1 = "e1",
        text = "",
        deleted = true,
      },
    }
    local shown_widgets, _, cleanup = open_deleted_annotations(tombstones)
    finally(cleanup)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)
    assert.are.equal("Highlight", menu.item_table[2].text)
  end)

  it("shortens long text to 47 characters and an ellipsis", function()
    local long_text = string.rep("a", 60)
    local tombstones = {
      {
        page = 1,
        pos0 = "d1",
        pos1 = "e1",
        text = long_text,
        deleted = true,
      },
    }
    local shown_widgets, _, cleanup = open_deleted_annotations(tombstones)
    finally(cleanup)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)
    assert.are.equal(string.rep("a", 47) .. "...", menu.item_table[2].text)
  end)

  it("never cuts a multi-byte character when it shortens long text", function()
    local text_utf8 = string.rep("中", 20)
    local tombstones = {
      {
        page = 1,
        pos0 = "d1",
        pos1 = "e1",
        text = text_utf8,
        deleted = true,
      },
    }
    local shown_widgets, _, cleanup = open_deleted_annotations(tombstones)
    finally(cleanup)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)
    local t = menu.item_table[2].text
    assert.is_true(t:sub(-3) == "...")
    assert.are.equal(t, util.fixUtf8(t, "?"))
  end)

  it("the restore confirmation shows the page number, not the EPUB position", function()
    local tombstones = {
      {
        page = "/body/DocFragment[2]/body/p[3]/text().0",
        pos0 = "/body/DocFragment[2]/body/p[3]/text().0",
        pos1 = "/body/DocFragment[2]/body/p[3]/text().10",
        pageno = 12,
        text = "Romeo",
        datetime = "2026-01-01 10:00:00",
        deleted = true,
      },
    }
    local shown_widgets, _, cleanup = open_deleted_annotations(tombstones)
    finally(cleanup)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)

    menu.item_table[2].callback()
    local confirm_box = shown_widgets[#shown_widgets]
    assert.is_not_nil(confirm_box)
    assert.is_truthy(confirm_box.text:find("Page 12: Romeo", 1, true))
    assert.is_nil(confirm_box.text:find("/body/", 1, true))
  end)

  it("Restore All of one annotation uses the singular", function()
    local tombstones = {
      {
        page = 1,
        pos0 = "d1",
        pos1 = "e1",
        text = "Sample",
        deleted = true,
      },
    }
    local shown_widgets, _, cleanup = open_deleted_annotations(tombstones)

    local captured_msg
    local orig_show_msg = utils.show_msg
    utils.show_msg = function(msg)
      captured_msg = msg
    end

    finally(function()
      utils.show_msg = orig_show_msg
      cleanup()
    end)

    local menu = shown_widgets[1]
    assert.is_not_nil(menu)

    menu.item_table[1].callback()
    local confirm_box = shown_widgets[#shown_widgets]
    assert.is_not_nil(confirm_box)
    assert.are.equal("Are you sure you want to restore 1 deleted annotation?", confirm_box.text)
    confirm_box.ok_callback()

    assert.are.equal("Restored 1 annotation.", captured_msg)
  end)
end)
