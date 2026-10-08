describe("AnnotationSync internationalization", function()
  local _
  local test_utils
  local test_data_dir = require("datastorage"):getDataDir() .. "/test_sync_i18n"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    _ = require("gettext")
  end)

  before_each(function()
    old_getDataDir = test_utils.setup_test_env(test_data_dir)
  end)

  after_each(function()
    test_utils.teardown_test_env(test_data_dir, old_getDataDir)
    -- Restore language to default
    _.changeLang("C")
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
    assert.are.equal("推送设置到云端", _("Push settings to cloud"))
    assert.are.equal("从云端拉取设置", _("Pull settings from cloud"))
    assert.are.equal("设备名称: %1", _("Device name: %1"))
    assert.are.equal("同步全部待同步书籍", _("Sync all pending books"))
    assert.are.equal(
      "正在后台依次同步 %1 本书",
      _.ngettext(
        "Syncing 1 book in the background",
        "Syncing %1 books one by one in the background",
        2
      )
    )

    -- Set language to Traditional Chinese (zh_TW)
    _.changeLang("zh_TW")
    assert.are.equal("標註同步", _("Annotation Sync"))
    assert.are.equal("推送設定至雲端", _("Push settings to cloud"))
    assert.are.equal("從雲端拉取設定", _("Pull settings from cloud"))
    assert.are.equal("裝置名稱: %1", _("Device name: %1"))
    assert.are.equal("同步全部待同步書籍", _("Sync all pending books"))
    assert.are.equal(
      "正在後台依序同步 %1 本書",
      _.ngettext(
        "Syncing 1 book in the background",
        "Syncing %1 books one by one in the background",
        2
      )
    )
  end)
end)
