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
    assert.are.equal("同步全部待同步书籍", _("Sync all pending books"))
    assert.are.equal(
      "正在后台依次同步 %1 本书",
      _.ngettext(
        "Syncing 1 book in the background",
        "Syncing %1 books one by one in the background",
        2
      )
    )

    assert.are.equal(
      "移到回收站",
      _("Move to trash")
    )
    assert.are.equal(
      "%1 在此设备上没有标注，但云存储中有 %2 条。要恢复，还是在所有设备上将其移到回收站？移到回收站的标注可以在“显示已删除的标注”中恢复。关闭此对话框也会恢复。",
      _.ngettext(
        "%1 has no annotations on this device, but 1 on your cloud storage. Restore it, or move it to the trash on all devices? Trashed annotations can be restored from 'Show deleted annotations'. Dismissing this dialog restores it as well.",
        "%1 has no annotations on this device, but %2 on your cloud storage. Restore them, or move them to the trash on all devices? Trashed annotations can be restored from 'Show deleted annotations'. Dismissing this dialog restores them as well.",
        3
      )
    )
    assert.are.equal(
      "上传设置到云端",
      _("Push settings to cloud")
    )
    assert.are.equal(
      "已恢复 %1 条标注。",
      _("Restored %1 annotations.")
    )
    assert.are.equal(
      "无法读取 %1，已跳过同步。",
      _("Cannot read %1. Skipped syncing it.")
    )
    assert.are.equal(
      "已成功导入 %1 项设置。",
      _.ngettext(
        "Successfully imported 1 setting.",
        "Successfully imported %1 settings.",
        1
      )
    )
    -- Set language to Traditional Chinese (zh_TW)
    _.changeLang("zh_TW")
    assert.are.equal("標註同步", _("Annotation Sync"))
    assert.are.equal("同步全部待同步書籍", _("Sync all pending books"))
    assert.are.equal(
      "正在後台依序同步 %1 本書",
      _.ngettext(
        "Syncing 1 book in the background",
        "Syncing %1 books one by one in the background",
        2
      )
    )
    assert.are.equal(
      "移至垃圾桶",
      _("Move to trash")
    )
    assert.are.equal(
      "%1 在此裝置上沒有標註，但雲端儲存中有 %2 條。要還原，還是在所有裝置上將其移至垃圾桶？移至垃圾桶的標註可以在「顯示已刪除的標註」中還原。關閉此對話框也會還原。",
      _.ngettext(
        "%1 has no annotations on this device, but 1 on your cloud storage. Restore it, or move it to the trash on all devices? Trashed annotations can be restored from 'Show deleted annotations'. Dismissing this dialog restores it as well.",
        "%1 has no annotations on this device, but %2 on your cloud storage. Restore them, or move them to the trash on all devices? Trashed annotations can be restored from 'Show deleted annotations'. Dismissing this dialog restores them as well.",
        3
      )
    )
    assert.are.equal(
      "上傳設定至雲端",
      _("Push settings to cloud")
    )
    assert.are.equal(
      "已還原 %1 條標註。",
      _("Restored %1 annotations.")
    )
    assert.are.equal(
      "無法讀取 %1，已跳過同步。",
      _("Cannot read %1. Skipped syncing it.")
    )
    assert.are.equal(
      "已成功匯入 %1 項設定。",
      _.ngettext(
        "Successfully imported 1 setting.",
        "Successfully imported %1 settings.",
        1
      )
    )
  end)
end)
