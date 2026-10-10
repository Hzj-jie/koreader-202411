describe("AnnotationSync menus, lifecycle, and settings edge cases", function()
  local AnnotationSyncPlugin, DataStorage, Device, LuaDefaults, LuaSettings
  local SettingsSelection, SyncService, UIManager
  local annotations, dump, json, menus, readhistory, remote, test_utils, util, utils
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_menus_lifecycle_tmp"
  local old_getDataDir

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()

    DataStorage = require("datastorage")
    Device = require("device")
    LuaDefaults = require("luadefaults")
    LuaSettings = require("luasettings")
    SyncService = require("apps/cloudstorage/syncservice")
    UIManager = require("ui/uimanager")
    dump = require("dump")
    json = require("json")
    readhistory = require("readhistory")
    util = require("util")

    AnnotationSyncPlugin = require("plugins/AnnotationSync.koplugin/main")
    SettingsSelection =
      require("plugins/AnnotationSync.koplugin/settings_selection")
    annotations = require("plugins/AnnotationSync.koplugin/annotations")
    menus = require("plugins/AnnotationSync.koplugin/menus")
    remote = require("plugins/AnnotationSync.koplugin/remote")
    utils = require("plugins/AnnotationSync.koplugin/utils")

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
    sync_instance.path = "plugins/AnnotationSync.koplugin"
    UIManager:show(readerui)
    fastforward_ui_events()
    os.remove(sync_instance.manager:changedDocumentsFile())
  end)

  after_each(function()
    if readerui then
      readerui:onExit(true)
      readerui:onClose()
    end
  end)

  describe("settings migration and menu actions", function()
    it(
      "migrates legacy cloud_server_object and annotation_sync_use_filename on init",
      function()
        finally(function()
          G_reader_settings:delete("cloud_server_object")
          G_reader_settings:delete("annotation_sync_use_filename")
          sync_instance.settings.use_filename = false
          sync_instance:saveSettings()
        end)

        sync_instance.settings.sync_server = nil
        setmetatable(sync_instance.settings, nil)
        G_reader_settings:save(sync_instance.plugin_id, {
          last_sync = "Never",
          use_filename = false,
          network_auto_sync = false,
          device_name = "",
          selected_settings = {},
        })
        G_reader_settings:save(
          "cloud_server_object",
          json.encode({ url = "http://legacy-webdav", type = "webdav" })
        )
        G_reader_settings:save("annotation_sync_use_filename", true)

        local old_register = readerui.menu.registerToMainMenu
        readerui.menu.registerToMainMenu = function() end
        sync_instance:init()
        readerui.menu.registerToMainMenu = old_register

        assert.are.same(
          { url = "http://legacy-webdav", type = "webdav" },
          sync_instance.settings.sync_server
        )
        assert.is_true(sync_instance.settings.use_filename)
        assert.is_false(G_reader_settings:has("annotation_sync_use_filename"))
      end
    )

    it(
      "exercises Settings submenu items, Cloud settings confirm, and main menu callbacks",
      function()
        local shown_widgets = {}
        local old_show = UIManager.show
        finally(function()
          UIManager.show = old_show
          sync_instance.settings.use_filename = false
          sync_instance.settings.network_auto_sync = false
          sync_instance.settings.device_name = ""
          sync_instance:saveSettings()
          G_reader_settings:delete("cloud_download_dir")
          G_reader_settings:delete("cloud_server_object")
          G_reader_settings:delete("cloud_provider_type")
          for _, w in ipairs(shown_widgets) do
            UIManager:closeIfShown(w)
          end
        end)
        UIManager.show = function(self, widget, ...)
          table.insert(shown_widgets, widget)
          return old_show(self, widget, ...)
        end

        local menu_items = {}
        sync_instance:addToMainMenu(menu_items)
        local root_sub = menu_items.annotation_sync_plugin.sub_item_table
        local settings_sub = root_sub[1].sub_item_table

        -- 1. Cloud settings item
        local cloud_item = settings_sub[1]
        cloud_item.callback()
        local sync_service_widget = shown_widgets[#shown_widgets]
        assert.is_not_nil(sync_service_widget)
        sync_service_widget.onConfirm({
          url = "http://cloud-confirm",
          type = "dropbox",
        })
        assert.are.equal(
          "http://cloud-confirm",
          G_reader_settings:read("cloud_download_dir")
        )
        assert.are.equal(
          "dropbox",
          G_reader_settings:read("cloud_provider_type")
        )
        assert.are.equal(
          "Current cloud: http://cloud-confirm",
          settings_sub[6].text_func()
        )

        -- 2. Use filename instead of hash
        local filename_item = settings_sub[2]
        assert.is_false(filename_item.checked_func())
        filename_item.callback()
        assert.is_true(filename_item.checked_func())
        filename_item.callback()
        assert.is_false(filename_item.checked_func())

        -- 3. Sync pending books automatically
        local auto_item = settings_sub[3]
        assert.is_false(auto_item.checked_func())
        auto_item.callback()
        assert.is_true(auto_item.checked_func())
        auto_item.callback()
        assert.is_false(auto_item.checked_func())

        -- 4. Device name InputDialog
        local device_item = settings_sub[4]
        assert.is_true(device_item.enabled_func())
        assert.are.equal(
          "Device name: " .. tostring(Device.model or "unknown"),
          device_item.text_func()
        )
        device_item.callback()
        local input_dialog
        for i = #shown_widgets, 1, -1 do
          if shown_widgets[i].title == "Set device name" then
            input_dialog = shown_widgets[i]
            break
          end
        end
        assert.is_not_nil(input_dialog)
        assert.are.equal("Set device name", input_dialog.title)
        assert.is_true(input_dialog.save_callback("  Bedroom Kobo  "))
        assert.are.equal("Bedroom Kobo", sync_instance.settings.device_name)
        assert.are.equal("Bedroom Kobo", sync_instance.manager:getDeviceName())
        assert.are.equal("Device name: Bedroom Kobo", device_item.text_func())

        assert.is_true(
          input_dialog.save_callback(" " .. tostring(Device.model) .. " ")
        )
        assert.are.equal("", sync_instance.settings.device_name)

        -- 5. Show changed settings item
        local changed_settings_item = settings_sub[5]
        changed_settings_item.callback()
        assert.are.equal(
          "Changed Settings",
          shown_widgets[#shown_widgets].title
        )

        -- 6. Push/Pull/Sync current/Sync all/Pending/Deleted/Last sync/Version items
        assert.is_true(root_sub[2].enabled_func())
        assert.is_true(root_sub[3].enabled_func())
        assert.is_true(root_sub[4].enabled_func())
        root_sub[4].hold_callback()
        assert.are.equal(
          "Sync annotations and bookmarks of the current book.",
          shown_widgets[#shown_widgets].text
        )

        assert.is_true(root_sub[5].enabled_func())
        root_sub[5].hold_callback()
        assert.are.equal(
          "Sync annotations and bookmarks of all pending books.",
          shown_widgets[#shown_widgets].text
        )
        root_sub[5].callback()
        assert.are.equal("No pending books.", shown_widgets[#shown_widgets].text)

        assert.is_true(root_sub[7].enabled_func())
        root_sub[7].callback()
        assert.are.equal("No pending books.", shown_widgets[#shown_widgets].text)

        assert.is_true(root_sub[8].enabled_func())
        root_sub[8].callback()
        assert.are.equal(
          "No deleted annotations found for this document.",
          shown_widgets[#shown_widgets].text
        )

        assert.are.equal("Last sync: Never", root_sub[9].text_func())

        sync_instance.fullname = "Annotation Sync"
        sync_instance.description = "Syncs annotations"
        assert.is_true(root_sub[10].keep_menu_open)
        root_sub[10].callback()
        assert.is_truthy(
          shown_widgets[#shown_widgets].text:find("Annotation Sync", 1, true)
        )
      end
    )

    it(
      "scans reading history via 'Add books from reading history' menu item",
      function()
        local shown_texts = {}
        local old_show = UIManager.show
        local old_hist = readhistory.hist
        finally(function()
          UIManager.show = old_show
          readhistory.hist = old_hist
        end)
        UIManager.show = function(self, widget, ...)
          if widget and type(widget.text) == "string" then
            table.insert(shown_texts, widget.text)
          end
          return old_show(self, widget, ...)
        end

        local doc_file = readerui.document.file
        readerui.doc_settings:save("annotations", {
          { page = 1, pos0 = "p0", pos1 = "p1", text = "Highlight" },
        })
        readerui.doc_settings:flush()
        readhistory.hist = {
          { file = doc_file },
          { file = doc_file },
          { file = test_data_dir .. "/nonexistent.epub" },
        }

        local menu_items = {}
        sync_instance:addToMainMenu(menu_items)
        local history_item =
          menu_items.annotation_sync_plugin.sub_item_table[6]
        assert.is_true(history_item.enabled_func())

        history_item.callback()
        assert.are.equal(
          "Adding books from reading history…\nThis may take a while if the history is long.",
          shown_texts[1]
        )

        fastforward_ui_events()
        assert.are.equal(
          "1 book from reading history is pending.\nSyncing it may take a while and slow KOReader down.",
          shown_texts[2]
        )
        local count, pending = sync_instance.manager:getPendingChangedDocuments()
        assert.are.equal(1, count)
        assert.are.same({ doc_file }, pending)
      end
    )
  end)

  describe(
    "dispatcher handlers, manualSync, applySyncedAnnotations, restoreAnnotations, and onAnnotationsModified",
    function()
      it(
        "delegates dispatcher events and onNetworkOnline to manager/plugin methods",
        function()
          local called = {}
          local orig_sync_all = sync_instance.manager.syncAllChangedDocuments
          local orig_manual = sync_instance.manualSync
          local orig_push = sync_instance.manager.pushSettings
          local orig_pull = sync_instance.manager.pullSettings
          local orig_dispatch = sync_instance.manager._dispatchNextSync
          finally(function()
            sync_instance.manager.syncAllChangedDocuments = orig_sync_all
            sync_instance.manualSync = orig_manual
            sync_instance.manager.pushSettings = orig_push
            sync_instance.manager.pullSettings = orig_pull
            sync_instance.manager._dispatchNextSync = orig_dispatch
          end)

          sync_instance.manager.syncAllChangedDocuments = function()
            called.sync_all = true
          end
          sync_instance.manualSync = function()
            called.manual_sync = true
          end
          sync_instance.manager.pushSettings = function()
            called.push_settings = true
          end
          sync_instance.manager.pullSettings = function()
            called.pull_settings = true
          end
          sync_instance.manager._dispatchNextSync = function()
            called.dispatch = true
            return true
          end

          assert.is_true(sync_instance:onAnnotationSyncSyncAll())
          assert.is_true(sync_instance:onAnnotationSyncManualSync())
          assert.is_true(sync_instance:onAnnotationSyncPushSettings())
          assert.is_true(sync_instance:onAnnotationSyncPullSettings())
          sync_instance:onNetworkOnline()

          assert.is_true(called.sync_all)
          assert.is_true(called.manual_sync)
          assert.is_true(called.push_settings)
          assert.is_true(called.pull_settings)
          assert.is_true(called.dispatch)
        end
      )

      it(
        "shows 'No book is open.' when manualSync is called without an open document",
        function()
          local orig_doc = readerui.document
          local shown_text
          local orig_show = UIManager.show
          finally(function()
            readerui.document = orig_doc
            UIManager.show = orig_show
          end)
          readerui.document = nil
          UIManager.show = function(_, widget)
            if widget and widget.text then
              shown_text = widget.text
            end
          end

          sync_instance:manualSync()
          assert.are.equal("No book is open.", shown_text)
        end
      )

      it(
        "applies synced annotations to an inactive document sidecar and shows non-silent restore messages",
        function()
          local inactive_file = test_data_dir .. "/inactive_book.epub"
          local ffiutil = require("ffi/util")
          ffiutil.copyFile(readerui.document.file, inactive_file)
          local shown_texts = {}
          local orig_show = UIManager.show
          finally(function()
            UIManager.show = orig_show
            os.remove(inactive_file)
            os.execute(
              "rm -rf " .. (inactive_file:gsub("%.epub$", ".sdr"))
            )
          end)
          UIManager.show = function(_, widget)
            if widget and widget.text then
              table.insert(shown_texts, widget.text)
            end
          end

          local merged = {
            {
              page = "/body/DocFragment[1]/body/p[1]",
              pos0 = "/body/DocFragment[1]/body/p[1]/text().0",
              pos1 = "/body/DocFragment[1]/body/p[1]/text().5",
              text = "Inactive highlight",
              drawer = "lighten",
              datetime = "2026-01-01 10:00:00",
            },
          }
          sync_instance:applySyncedAnnotations({ file = inactive_file }, merged)
          local loaded =
            sync_instance.manager:getAnnotationsForDocument(inactive_file)
          assert.are.equal(1, #loaded)
          assert.are.equal("Inactive highlight", loaded[1].text)

          sync_instance:restoreAnnotations({
            {
              page = "/body/DocFragment[1]/body/p[1]",
              pos0 = "/body/DocFragment[1]/body/p[1]/text().0",
              pos1 = "/body/DocFragment[1]/body/p[1]/text().5",
              text = "One",
              deleted = true,
            },
          }, false)
          assert.are.equal("Annotation restored.", shown_texts[1])

          sync_instance:restoreAnnotations({
            {
              page = "/body/DocFragment[1]/body/p[2]",
              pos0 = "/body/DocFragment[1]/body/p[2]/text().0",
              pos1 = "/body/DocFragment[1]/body/p[2]/text().5",
              text = "Two",
              deleted = true,
            },
            {
              page = "/body/DocFragment[1]/body/p[3]",
              pos0 = "/body/DocFragment[1]/body/p[3]/text().0",
              pos1 = "/body/DocFragment[1]/body/p[3]/text().5",
              text = "Three",
              deleted = true,
            },
          }, false)
          assert.are.equal("Restored 2 annotations.", shown_texts[2])
        end
      )

      it(
        "handles onAnnotationsModified during apply, closed-book book_path deduplication, and unknown_file",
        function()
          local orig_doc = readerui.document
          finally(function()
            readerui.document = orig_doc
            sync_instance.is_applying_sync = false
          end)

          sync_instance.is_applying_sync = true
          sync_instance:onAnnotationsModified({ { text = "ignored" } })
          assert.are.equal(
            0,
            (sync_instance.manager:getPendingChangedDocuments())
          )
          sync_instance.is_applying_sync = false

          local closed_path = test_data_dir .. "/closed.epub"
          sync_instance:onAnnotationsModified({
            { book_path = closed_path, text = "first" },
            { book_path = closed_path, text = "second" },
          })
          local count, list =
            sync_instance.manager:getPendingChangedDocuments()
          assert.are.equal(1, count)
          assert.are.same({ closed_path }, list)

          os.remove(sync_instance.manager:changedDocumentsFile())
          readerui.document = nil
          sync_instance:onAnnotationsModified({ { text = "no doc and no path" } })
          assert.are.equal(
            0,
            (sync_instance.manager:getPendingChangedDocuments())
          )
        end
      )
    end
  )

  describe("menus.lua edge cases", function()
    it(
      "formats fallback/truncated labels in show_deleted_annotations and supports Restore All",
      function()
        local shown_widgets = {}
        local orig_show = UIManager.show
        local sync_cache_path =
          sync_instance.manager:getSyncCachePath(readerui.document.file)
        finally(function()
          UIManager.show = orig_show
          os.remove(sync_cache_path)
          for _, w in ipairs(shown_widgets) do
            UIManager:closeIfShown(w)
          end
        end)
        UIManager.show = function(self, widget, ...)
          table.insert(shown_widgets, widget)
          return orig_show(self, widget, ...)
        end

        local long_text = string.rep("A", 60)
        local f = io.open(sync_cache_path, "w")
        f:write(json.encode({
          {
            page = "/body/DocFragment[1]/body/p[1]",
            pos0 = "/body/DocFragment[1]/body/p[1]/text().0",
            pos1 = "/body/DocFragment[1]/body/p[1]/text().5",
            text = "",
            note = "",
            deleted = true,
          },
          {
            page = "/body/DocFragment[1]/body/p[2]",
            pos0 = "/body/DocFragment[1]/body/p[2]/text().0",
            pos1 = "/body/DocFragment[1]/body/p[2]/text().5",
            text = long_text,
            deleted = true,
          },
        }))
        f:close()

        menus.show_deleted_annotations(sync_instance, readerui.document)
        local deleted_menu = shown_widgets[#shown_widgets]
        assert.are.equal("Deleted Annotations", deleted_menu.title)
        assert.are.equal("Restore All", deleted_menu.item_table[1].text)
        assert.are.equal("Highlight", deleted_menu.item_table[2].text)
        assert.are.equal(
          string.rep("A", 47) .. "...",
          deleted_menu.item_table[3].text
        )

        -- Trigger Restore All ConfirmBox and confirm
        deleted_menu.item_table[1].callback()
        local confirm_box = shown_widgets[#shown_widgets]
        confirm_box.ok_callback()
        assert.are.equal(2, #readerui.annotation.annotations)
        assert.are.equal(
          "Restored 2 annotations.",
          shown_widgets[#shown_widgets].text
        )
      end
    )

    it(
      "filters current device, sorts other devices alphabetically, and opens differing settings menu",
      function()
        local shown_widgets = {}
        local orig_show = UIManager.show
        finally(function()
          UIManager.show = orig_show
          sync_instance.settings.device_name = ""
          for _, w in ipairs(shown_widgets) do
            UIManager:closeIfShown(w)
          end
        end)
        UIManager.show = function(self, widget, ...)
          table.insert(shown_widgets, widget)
          return orig_show(self, widget, ...)
        end

        sync_instance.settings.device_name = "ThisDevice"
        menus.show_devices_menu(sync_instance, {
          ["ThisDevice"] = { timestamp = "2026-01-01", settings = {} },
        })
        assert.are.equal(
          "No other devices found in cloud settings.",
          shown_widgets[#shown_widgets].text
        )

        menus.show_devices_menu(sync_instance, {
          ["ThisDevice"] = { timestamp = "2026-01-01", settings = {} },
          ["ZetaDevice"] = { settings = {} },
          ["AlphaDevice"] = {
            timestamp = "2026-01-02",
            settings = {},
          },
        })
        local dev_menu = shown_widgets[#shown_widgets]
        assert.are.equal(2, #dev_menu.item_table)
        assert.are.equal(
          "AlphaDevice (2026-01-02)",
          dev_menu.item_table[1].text
        )
        assert.are.equal("ZetaDevice (unknown)", dev_menu.item_table[2].text)

        -- Tapping AlphaDevice with empty settings shows 'No differing settings found for this device.'
        dev_menu.item_table[1].callback()
        assert.are.equal(
          "No differing settings found for this device.",
          shown_widgets[#shown_widgets].text
        )
      end
    )

    it(
      "formats nil, boolean, and table values in show_differing_settings_menu and handles Select All / Clear Selection",
      function()
        local shown_widgets = {}
        local orig_show = UIManager.show
        finally(function()
          UIManager.show = orig_show
          for _, w in ipairs(shown_widgets) do
            UIManager:closeIfShown(w)
          end
        end)
        UIManager.show = function(self, widget, ...)
          table.insert(shown_widgets, widget)
          return orig_show(self, widget, ...)
        end

        menus.show_differing_settings_menu(sync_instance, "RemoteReader", {
          ["reader:bool_opt"] = true,
          ["reader:table_opt"] = { nested = 1 },
        })
        local diff_menu = shown_widgets[#shown_widgets]
        assert.are.equal("Settings from RemoteReader", diff_menu.title)
        assert.are.equal(5, #diff_menu.item_table)
        assert.are.equal(
          "[✓] [reader] bool_opt: nil -> true",
          diff_menu.item_table[4].text_func()
        )
        assert.are.equal(
          "[✓] [reader] table_opt: nil -> {...}",
          diff_menu.item_table[5].text_func()
        )

        -- Toggle individual item off and back via Select All
        diff_menu.item_table[4].callback()
        assert.are.equal(
          "[ ] [reader] bool_opt: nil -> true",
          diff_menu.item_table[4].text_func()
        )
        diff_menu.item_table[2].callback()
        assert.are.equal(
          "[✓] [reader] bool_opt: nil -> true",
          diff_menu.item_table[4].text_func()
        )

        -- Clear Selection, then Import Selected Settings -> 'No settings imported.'
        diff_menu.item_table[3].callback()
        assert.are.equal(
          "[ ] [reader] bool_opt: nil -> true",
          diff_menu.item_table[4].text_func()
        )
        diff_menu.item_table[1].callback()
        assert.are.equal(
          "No settings imported.",
          shown_widgets[#shown_widgets].text
        )
      end
    )
  end)

  describe(
    "manager, settings_selection, remote, annotations, and utils edge cases",
    function()
      it(
        "migrates legacy map format in changed_documents.lua to an array",
        function()
          local legacy_path = sync_instance.manager:changedDocumentsFile()
          util.writeToFile(
            dump({ [test_data_dir .. "/legacy.epub"] = true }),
            legacy_path,
            true
          )

          local count, docs =
            sync_instance.manager:getPendingChangedDocuments()
          assert.are.equal(1, count)
          assert.are.same({ test_data_dir .. "/legacy.epub" }, docs)
        end
      )

      it(
        "handles pushSettings error/empty paths, pullSettings failure, and remote missing sync_server",
        function()
          local shown_texts = {}
          local orig_show = UIManager.show
          local orig_write = util.writeToFile
          finally(function()
            UIManager.show = orig_show
            util.writeToFile = orig_write
            sync_instance.settings.selected_settings = {}
          end)
          UIManager.show = function(_, widget)
            if widget and widget.text then
              table.insert(shown_texts, widget.text)
            end
          end

          sync_instance.settings.selected_settings = {}
          sync_instance.manager:pushSettings()
          assert.are.equal(
            "No settings are selected. Please select settings to sync in 'Show changed settings'.",
            shown_texts[#shown_texts]
          )

          sync_instance.settings.selected_settings = {
            ["reader:auto_standby_timeout_seconds"] = true,
          }
          util.writeToFile = function()
            return false, "disk full"
          end
          sync_instance.manager:pushSettings()
          assert.are.equal(
            "Failed to write settings to local storage.",
            shown_texts[#shown_texts]
          )
          util.writeToFile = orig_write

          -- When sync_server is nil, pullSettings shows 'No cloud destination set in settings.' and then 'Failed to fetch settings from cloud'
          sync_instance.settings.sync_server = nil
          setmetatable(sync_instance.settings, nil)
          G_reader_settings:delete("cloud_server_object")
          sync_instance.manager:pullSettings()
          assert.are.equal(
            "Failed to fetch settings from cloud",
            shown_texts[#shown_texts]
          )

          -- And remote.sync_annotations with no sync_server fails silently via on_complete(false)
          local tmp_json = test_data_dir .. "/no_server.json"
          util.writeToFile("{}", tmp_json)
          local completed_status
          pcall(function()
            remote.sync_annotations(sync_instance, tmp_json, function(ok)
              completed_status = ok
            end)
          end)
          assert.is_false(completed_status)
        end
      )

      it(
        "writes nested settings/<name> keys, overwrites scalar parents, and rejects invalid setting keys",
        function()
          local gestures_path =
            DataStorage:getSettingsDir() .. "/gestures.lua"
          finally(function()
            os.remove(gestures_path)
          end)

          assert.is_nil(
            sync_instance.manager:getLocalSettingValue("no_colon", {})
          )
          assert.is_nil(
            sync_instance.manager:getLocalSettingValue("unknown:foo", {})
          )
          assert.is_false(
            sync_instance.manager:_writeLocalSettingValue("no_colon", 1)
          )
          assert.is_false(
            sync_instance.manager:_writeLocalSettingValue("unknown:foo", 1)
          )

          assert.is_true(
            sync_instance.manager:_writeLocalSettingValue(
              "settings/gestures:custom_tap",
              "scalar_value"
            )
          )
          assert.is_true(
            sync_instance.manager:_writeLocalSettingValue(
              "settings/gestures:custom_tap.corner.action",
              "toggle_frontlight"
            )
          )
          assert.are.equal(
            "toggle_frontlight",
            sync_instance.manager:getLocalSettingValue(
              "settings/gestures:custom_tap.corner.action",
              {}
            )
          )
        end
      )

      it(
        "supports Select All, Clear Selection, branch navigation, and array formatting in SettingsSelection",
        function()
          local gestures_path =
            DataStorage:getSettingsDir() .. "/gestures.lua"
          local shown_menus = {}
          local orig_show = UIManager.show
          finally(function()
            UIManager.show = orig_show
            G_reader_settings:delete("copt_font_gamma")
            os.remove(gestures_path)
            for _, w in ipairs(shown_menus) do
              UIManager:closeIfShown(w)
            end
          end)
          UIManager.show = function(self, widget, ...)
            table.insert(shown_menus, widget)
            return orig_show(self, widget, ...)
          end

          local g_settings = LuaSettings:open(gestures_path)
          g_settings:save("gesture_fm", { tap_top_right_corner = "custom" })
          g_settings:flush()
          G_reader_settings:save("copt_font_gamma", { 10, 20 })

          SettingsSelection.show(sync_instance)
          local root_menu = shown_menus[#shown_menus]
          assert.are.equal("Changed Settings", root_menu.title)

          -- Test Select All and Clear Selection on root menu
          root_menu.item_table[1].callback()
          assert.is_true(
            sync_instance.settings.selected_settings["reader:copt_font_gamma"]
          )
          root_menu.item_table[2].callback()
          assert.is_nil(
            sync_instance.settings.selected_settings["reader:copt_font_gamma"]
          )

          local found_array = false
          local gestures_branch_item
          for _, item in ipairs(root_menu.item_table) do
            local txt = item.text or (item.text_func and item.text_func()) or ""
            if txt:find("copt_font_gamma: nil -> [10, 20]", 1, true) then
              found_array = true
            end
            if txt:find("[settings/gestures] gestures >", 1, true) then
              gestures_branch_item = item
            end
          end
          assert.is_true(found_array)
          assert.is_not_nil(gestures_branch_item)

          -- Open gestures branch submenu
          gestures_branch_item.callback()
          local branch_menu = shown_menus[#shown_menus]
          assert.are.equal("gestures", branch_menu.title)
        end
      )

      it(
        "covers annotations.sort coordinate ordering and utils.read_json error cases",
        function()
          assert.is_false(
            annotations.write_annotations_json({}, nil, "out.json")
          )

          local items = {
            {
              page = 1,
              pos0 = { x = 20, y = 10, page = 1 },
              text = "right",
            },
            {
              page = 1,
              pos0 = { x = 10, y = 10, page = 1 },
              text = "left",
            },
            {
              page = 1,
              pos0 = { x = 10, y = 5, page = 1 },
              text = "top",
            },
            {
              page = 1,
              pos0 = "bookmark_without_coords",
              text = "bookmark",
            },
          }
          annotations.sort(items)
          assert.are.equal("bookmark", items[1].text)
          assert.are.equal("top", items[2].text)
          assert.are.equal("left", items[3].text)
          assert.are.equal("right", items[4].text)

          assert.is_nil(utils.read_json(nil))
          assert.is_nil(utils.read_json(test_data_dir .. "/missing.json"))
          local html_path = test_data_dir .. "/error.html"
          local err_json_path = test_data_dir .. "/api_error.json"
          finally(function()
            os.remove(html_path)
            os.remove(err_json_path)
          end)
          util.writeToFile("<html>502 Bad Gateway</html>", html_path)
          assert.is_nil(utils.read_json(html_path))

          util.writeToFile(
            '{"error_summary": "path/not_found/.."}',
            err_json_path
          )
          assert.is_nil(utils.read_json(err_json_path))

          assert.is_nil(utils.get_nested_value(nil, "a.b"))
          assert.is_nil(utils.get_nested_value({ a = 42 }, "a.b.c"))
        end
      )

      it(
        "preserves imported defaults: settings in G_defaults and on disk after G_defaults:flush()",
        function()
          local orig_defaults = _G.G_defaults
          local custom_defaults_path =
            DataStorage:getDataDir() .. "/defaults.custom.lua"
          finally(function()
            _G.G_defaults = orig_defaults
            os.remove(custom_defaults_path)
          end)

          -- Match real KOReader (reader.lua / luadefaults.lua), where G_defaults is opened against DataStorage:getDataDir()
          _G.G_defaults = LuaDefaults:open(DataStorage:getDataDir())
          assert.are.equal(
            16,
            _G.G_defaults:read("DCREREADER_CONFIG_DEFAULT_FONT_SIZE")
          )

          assert.is_true(
            sync_instance.manager:_writeLocalSettingValue(
              "defaults:DCREREADER_CONFIG_DEFAULT_FONT_SIZE",
              28
            )
          )

          -- Both G_defaults in memory and getLocalSettingValue (which calls G_defaults:flush()) must reflect 28
          assert.are.equal(
            28,
            _G.G_defaults:read("DCREREADER_CONFIG_DEFAULT_FONT_SIZE")
          )
          assert.are.equal(
            28,
            sync_instance.manager:getLocalSettingValue(
              "defaults:DCREREADER_CONFIG_DEFAULT_FONT_SIZE",
              {}
            )
          )
        end
      )

      it(
        "recurses into dictionary settings whose vanilla default in settings.reader.lua is an empty table",
        function()
          local shown_menu
          local orig_show = UIManager.show
          finally(function()
            UIManager.show = orig_show
            G_reader_settings:delete("readtimer")
            if shown_menu then
              UIManager:closeIfShown(shown_menu)
            end
          end)
          UIManager.show = function(self, widget, ...)
            if widget and widget.title == "Changed Settings" then
              shown_menu = widget
            end
            return orig_show(self, widget, ...)
          end

          -- In defaults/settings.reader.lua, readtimer defaults to {} (an empty table)
          G_reader_settings:save("readtimer", {
            remain_time = 600,
          })

          SettingsSelection.show(sync_instance)
          assert.is_not_nil(shown_menu)

          local readtimer_branch
          for _, item in ipairs(shown_menu.item_table) do
            local txt = item.text or (item.text_func and item.text_func()) or ""
            if txt:find("[reader] readtimer >", 1, true) then
              readtimer_branch = item
              break
            end
          end

          assert.is_not_nil(readtimer_branch)
        end
      )
    end
  )
end)
