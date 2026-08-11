describe("AnnotationSync internationalization", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json
  local _
  local readerui, sync_instance
  local test_data_dir = "test_sync_i18n"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/spec/unit/test_utils")
    disable_plugins()
    _ = require("gettext")
    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
  end)

  before_each(function()
    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  after_each(function()
    if readerui then
      readerui:onClose()
    end
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    -- Restore language to default
    if _ and _.changeLang then
      _.changeLang("C")
    end
  end)

  it(
    "verifies dynamic translation loading during plugin initialization",
    function()
      -- Save original language state
      local old_lang = _.current_lang

      -- Set the language to Italian (it_IT)
      _.current_lang = "it_IT"

      -- Initialize the plugin context using standard helper
      readerui, sync_instance = test_utils.init_integration_context(
        "spec/front/unit/data/juliet.epub",
        AnnotationSyncPlugin
      )

      -- Verify that strings are correctly translated to Italian
      assert.are.equal("Sincronizzazione Annotazioni", _("Annotation Sync"))
      assert.are.equal("Impostazioni", _("Settings"))

      -- Set language to Simplified Chinese (zh_CN)
      _.current_lang = "zh_CN"
      for k in pairs(_.translation) do
        _.translation[k] = nil
      end
      sync_instance:init()
      assert.are.equal("标注同步", _("Annotation Sync"))
      assert.are.equal("全部同步", _("Sync All"))
      assert.are.equal("全部同步已取消。", _("Sync All cancelled."))

      -- Set language to Traditional Chinese (zh_TW)
      _.current_lang = "zh_TW"
      for k in pairs(_.translation) do
        _.translation[k] = nil
      end
      sync_instance:init()
      assert.are.equal("標註同步", _("Annotation Sync"))
      assert.are.equal("全部同步", _("Sync All"))
      assert.are.equal("全部同步已取消。", _("Sync All cancelled."))

      -- Restore original language
      _.current_lang = old_lang
    end
  )
end)
