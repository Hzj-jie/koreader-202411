describe("AnnotationSync Highlight Ground Truth Integration", function()
  local UIManager
  local AnnotationSyncPlugin, highlight_db, test_utils, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_sync_ground_truth_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    util = require("util")

    highlight_db = require("plugins/AnnotationSync.koplugin/highlight_db")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")

    old_getDataDir = test_utils.setup_test_env(test_data_dir)
    _G.old_ImageViewer_new = test_utils.mock_image_viewer()

    G_reader_settings:save("default_highlight_action", "highlight")

    readerui, sync_instance = test_utils.init_integration_context(
      "spec/front/unit/data/juliet.epub",
      AnnotationSyncPlugin
    )
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
    UIManager:show(readerui)
    fastforward_ui_events()
    readerui.annotation.annotations = {}
    os.remove(sync_instance.manager:changedDocumentsFile())
  end)

  it(
    "should generate highlights for selected ground truth entries and track them",
    function()
      local test_entries = {
        {
          page_num = highlight_db[26].page_num, -- Page 6, Line 1 ("Act I")
          pos0 = highlight_db[26].pos0,
          pos1 = { x = 500, y = highlight_db[26].pos1.y },
          text = highlight_db[26].text,
        },
        {
          page_num = highlight_db[51].page_num, -- Page 7, Line 1 ("SCENE I. Verona. A public place.")
          pos0 = highlight_db[51].pos0,
          pos1 = { x = 500, y = highlight_db[51].pos1.y },
          text = highlight_db[51].text,
        },
      }

      for _, entry in ipairs(test_entries) do
        readerui.rolling:onGotoPage(entry.page_num)
        fastforward_ui_events()

        test_utils.emulate_highlight(readerui, entry)
      end

      assert.is_equal(#test_entries, #readerui.annotation.annotations)

      for i, entry in ipairs(test_entries) do
        local stored_ann = readerui.annotation.annotations[i]
        assert.is_equal(entry.text, stored_ann.text)
      end

      local count, changed_docs =
        sync_instance.manager:getPendingChangedDocuments()
      assert.is_equal(1, count)
      assert.truthy(util.arrayContains(changed_docs, readerui.document.file))
    end
  )
end)
