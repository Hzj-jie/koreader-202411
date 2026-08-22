describe("AnnotationSync internationalization", function()
  local _
  local test_utils
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_sync_i18n"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    test_utils = require("plugins/AnnotationSync.koplugin/spec/unit/test_utils")
    disable_plugins()
    _ = require("gettext")
  end)

  before_each(function()
    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  after_each(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    -- Restore language to default
    if _ and _.changeLang then
      _.changeLang("C")
    end
  end)

  it("verifies translation loading for supported locales", function()
    -- Set the language to Italian (it_IT)
    _.changeLang("it_IT")
    assert.are.equal("Sincronizzazione Annotazioni", _("Annotation Sync"))
    assert.are.equal("Impostazioni", _("Settings"))

    -- Set language to Hungarian (hu)
    _.changeLang("hu")
    assert.are.equal("Kiemelések szinkronizálása", _("Annotation Sync"))
    assert.are.equal("Beállítások", _("Settings"))

    -- Set language to Simplified Chinese (zh_CN)
    _.changeLang("zh_CN")
    assert.are.equal("标注同步", _("Annotation Sync"))
    assert.are.equal("全部同步", _("Sync All"))
    assert.are.equal("全部同步已取消。", _("Sync All cancelled."))

    -- Set language to Traditional Chinese (zh_TW)
    _.changeLang("zh_TW")
    assert.are.equal("標註同步", _("Annotation Sync"))
    assert.are.equal("全部同步", _("Sync All"))
    assert.are.equal("全部同步已取消。", _("Sync All cancelled."))

    -- Restore language to default
    _.changeLang("C")
  end)
end)
