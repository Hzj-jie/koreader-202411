describe("AnnotationSync Settings Synchronization", function()
  local UIManager, AnnotationSyncPlugin, test_utils, json, util
  local readerui, sync_instance
  local test_data_dir = require("datastorage"):getDataDir()
    .. "/test_settings_sync_tmp"
  local old_getDataDir, real_sync

  setup(function()
    require("commonrequire")
    local plugin_path = "plugins/AnnotationSync.koplugin/?.lua"
    package.path = plugin_path .. ";" .. package.path

    test_utils = require("plugins/AnnotationSync.koplugin/test_utils")
    disable_plugins()
    UIManager = require("ui/uimanager")
    json = require("json")
    util = require("util")
    real_sync = require("apps/cloudstorage/syncservice").sync
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
    sync_instance.path = "plugins/AnnotationSync.koplugin"
    UIManager:show(readerui)
    fastforward_ui_events()
  end)

  after_each(function()
    if readerui then
      readerui:onExit(true)
      readerui:onClose()
    end
  end)

  it(
    "should return nil from getSelectedSettingsWithValues when selected_settings is empty",
    function()
      sync_instance.settings.selected_settings = {}
      local res = sync_instance.manager:getSelectedSettingsWithValues()
      assert.is_nil(res)
    end
  )

  it("should retrieve selected settings with correct active values", function()
    finally(function()
      G_reader_settings:delete("auto_standby_timeout_seconds")
      G_reader_settings:delete("footer")
    end)
    G_reader_settings:save("auto_standby_timeout_seconds", 120)
    G_reader_settings:save("footer", { time = true })

    -- Select some settings
    sync_instance.settings.selected_settings = {
      ["reader:auto_standby_timeout_seconds"] = true,
      ["reader:footer.time"] = true,
    }

    local values = sync_instance.manager:getSelectedSettingsWithValues()
    assert.is_not_nil(values)
    assert.is_equal(120, values["reader:auto_standby_timeout_seconds"])
    assert.is_equal(true, values["reader:footer.time"])
  end)

  it(
    "should retrieve selected settings from defaults.custom.lua and settings/*.lua",
    function()
      local defaults_path = test_data_dir .. "/defaults.custom.lua"
      local profiles_path = test_data_dir .. "/settings/profiles.lua"
      finally(function()
        os.remove(defaults_path)
        os.remove(profiles_path)
      end)
      local f = io.open(defaults_path, "w")
      f:write([[return { ["DTAP_ZONE_MENU"] = { ["h"] = 0.25 } }]])
      f:close()
      f = io.open(profiles_path, "w")
      f:write([[return { ["night"] = { ["dark_mode"] = true } }]])
      f:close()

      sync_instance.settings.selected_settings = {
        ["defaults:DTAP_ZONE_MENU.h"] = true,
        ["settings/profiles:night.dark_mode"] = true,
        ["settings/missing:night.dark_mode"] = true,
        ["defaults:DTAP_ZONE_MENU"] = false,
      }

      assert.are.same({
        ["defaults:DTAP_ZONE_MENU.h"] = 0.25,
        ["settings/profiles:night.dark_mode"] = true,
      }, sync_instance.manager:getSelectedSettingsWithValues())
    end
  )

  it(
    "should correctly write local file and sync it using remote.push_settings",
    function()
      -- Configure mock sync server
      local test_server =
        { url = "http://test-server-settings", type = "webdav" }
      sync_instance:onSyncServiceConfirm(test_server)

      local SyncService = require("apps/cloudstorage/syncservice")
      local old_sync = SyncService.sync
      finally(function()
        G_reader_settings:delete("auto_suspend_timeout_seconds")
        SyncService.sync = old_sync
      end)
      G_reader_settings:save("auto_suspend_timeout_seconds", 300)

      -- Select the setting
      sync_instance.settings.selected_settings = {
        ["reader:auto_suspend_timeout_seconds"] = true,
      }

      -- Set custom device name
      sync_instance.settings.device_name = "TestDeviceX"

      -- Mock SyncService to assert the values being synced
      local sync_called = false
      local remote_file_content = nil

      SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
        sync_called = true
        -- Create a fake remote/income file with another device's settings
        local income_path = local_path .. ".income"
        local other_device_data = {
          ["OtherDevice"] = {
            settings = {
              ["reader:auto_standby_timeout_seconds"] = 15,
            },
            timestamp = "2026-06-06 12:00:00",
          },
        }
        local fi = io.open(income_path, "w")
        fi:write(json.encode(other_device_data))
        fi:close()

        local success, merged =
          callback(local_path, local_path .. ".last_sync", income_path)
        assert.is_true(success)

        -- Read local_path after callback to verify the merge
        local fl = io.open(local_path, "r")
        remote_file_content = fl:read("*a")
        fl:close()

        os.remove(income_path)
        if finish_cb then
          finish_cb(true)
        end
        return true
      end

      sync_instance.manager:pushSettings()
      assert.is_true(sync_called)

      -- Verify that the synced file has both this device's and other device's settings
      assert.is_not_nil(remote_file_content)
      local data = json.decode(remote_file_content)
      assert.is_not_nil(data["TestDeviceX"])
      assert.is_equal(
        300,
        data["TestDeviceX"].settings["reader:auto_suspend_timeout_seconds"]
      )
      assert.is_not_nil(data["OtherDevice"])
      assert.is_equal(
        15,
        data["OtherDevice"].settings["reader:auto_standby_timeout_seconds"]
      )
    end
  )

  it(
    "should correctly sync and pull settings from cloud, showing other devices and importing selection",
    function()
      -- Configure mock sync server
      local test_server =
        { url = "http://test-server-settings-pull", type = "webdav" }
      sync_instance:onSyncServiceConfirm(test_server)

      -- Mock SyncService to simulate pulling other devices' settings
      local sync_called = false
      local SyncService = require("apps/cloudstorage/syncservice")
      local old_sync = SyncService.sync
      local old_show = UIManager.show
      finally(function()
        G_reader_settings:delete("auto_suspend_timeout_seconds")
        G_reader_settings:delete("auto_standby_timeout_seconds")
        SyncService.sync = old_sync
        UIManager.show = old_show
      end)
      G_reader_settings:save("auto_suspend_timeout_seconds", 300)
      G_reader_settings:save("auto_standby_timeout_seconds", 100)
      SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
        sync_called = true
        local income_path = local_path .. ".income"
        -- Simulation: OtherDevice has differing auto_standby_timeout_seconds (50 instead of 100)
        local remote_data = {
          ["OtherDevice"] = {
            settings = {
              ["reader:auto_standby_timeout_seconds"] = 50,
              ["reader:auto_suspend_timeout_seconds"] = 300, -- same, so should not show
            },
            timestamp = "2026-06-06 13:00:00",
          },
        }
        local fi = io.open(income_path, "w")
        fi:write(json.encode(remote_data))
        fi:close()

        assert.is_nil(
          callback(local_path, local_path .. ".last_sync", income_path, 200)
        )

        os.remove(income_path)
        if finish_cb then
          finish_cb(nil)
        end
        return nil
      end

      -- Mock UIManager:show to capture the menu and trigger selection/import
      local show_called_count = 0
      UIManager.show = function(self, widget)
        if widget.text and not widget.title then
          return
        end
        show_called_count = show_called_count + 1
        if show_called_count == 1 then
          -- Device list menu. Let's select "OtherDevice (2026-06-06 13:00:00)"
          assert.is_equal("Pull settings from cloud", widget.title)
          assert.is_equal(1, #widget.item_table)
          assert.is_not_nil(widget.item_table[1].text:find("OtherDevice"))
          -- Trigger callback to open differing settings menu
          widget.item_table[1].callback()
        elseif show_called_count == 2 then
          -- Differing settings menu.
          assert.is_not_nil(widget.title:find("OtherDevice"))
          -- Items should be: "Import Selected Settings", "Select All", "Clear Selection", and then the setting item
          assert.is_equal(4, #widget.item_table)
          assert.is_not_nil(
            widget.item_table[4]
              .text_func()
              :find("auto_standby_timeout_seconds", 1, true)
          )
          assert.is_not_nil(
            widget.item_table[4].text_func():find("100 -> 50", 1, true)
          )

          -- Trigger "Import Selected Settings"
          widget.item_table[1].callback()
        end
      end

      sync_instance.manager:pullSettings()
      assert.is_true(sync_called)
      assert.is_equal(2, show_called_count)

      -- Verify that the setting was imported and saved locally
      local ok_read, data =
        pcall(dofile, test_data_dir .. "/settings.reader.lua")
      assert.is_true(ok_read)
      assert.is_equal(50, data.auto_standby_timeout_seconds)
    end
  )

  it(
    "compares pulled map settings by deep equality regardless of key order",
    function()
      -- 100 maps x 32 distinct keys per map fail against json.encode key ordering in 20/20 runs
      -- due to LuaJIT per-process string hash randomization.
      local remote_json_parts = { "{" }
      local map_names = {}
      for m = 1, 100 do
        local map_name = ("map_%03d"):format(m)
        table.insert(map_names, map_name)
        local map_data = {}
        table.insert(
          remote_json_parts,
          (m > 1 and ',"reader:%s":{' or '"reader:%s":{'):format(map_name)
        )
        for i = 1, 32 do
          local k = ("m%03d_k%02d"):format(m, i)
          map_data[k] = true
        end
        G_reader_settings:save(map_name, map_data)
        for i = 32, 1, -1 do
          local k = ("m%03d_k%02d"):format(m, i)
          table.insert(
            remote_json_parts,
            (i < 32 and ',"%s":true' or '"%s":true'):format(k)
          )
        end
        table.insert(remote_json_parts, "}")
      end
      table.insert(remote_json_parts, "}")

      local remote_settings = json.decode(table.concat(remote_json_parts))

      local shown = {}
      local old_show = UIManager.show
      finally(function()
        for _, name in ipairs(map_names) do
          G_reader_settings:delete(name)
        end
        UIManager.show = old_show
      end)
      UIManager.show = function(_, widget)
        table.insert(shown, tostring(widget.title or widget.text))
      end

      local menus = require("plugins/AnnotationSync.koplugin/menus")
      menus.show_differing_settings_menu(
        sync_instance,
        "OtherDevice",
        remote_settings,
        nil
      )

      assert.is_equal(1, #shown)
      assert.is_equal("No differing settings found for this device.", shown[1])
    end
  )

  describe("remote.push_settings finish_cb contract", function()
    local SyncService = require("apps/cloudstorage/syncservice")
    local remote = require("plugins/AnnotationSync.koplugin/remote")
    local old_sync

    before_each(function()
      old_sync = SyncService.sync
    end)

    after_each(function()
      SyncService.sync = old_sync
    end)

    it(
      "push_settings: on_complete is called only from finish_cb; postponed calls it later",
      function()
        local dummy_json = test_data_dir .. "/test_settings_case18.json"
        util.writeToFile("{}", dummy_json)

        local queued_finish = nil
        SyncService.sync = function(server, local_path, callback, is_silent, finish_cb)
          queued_finish = function()
            callback(
              local_path,
              local_path .. ".last_sync",
              local_path .. ".income"
            )
            if finish_cb then
              finish_cb(true)
            end
          end
        end

        local test_server = { url = "http://mock", type = "dropbox" }
        sync_instance:onSyncServiceConfirm(test_server)

        local on_complete_called = false
        local on_complete_success = nil
        remote.push_settings(sync_instance, dummy_json, function(success)
          on_complete_called = true
          on_complete_success = success
        end)

        -- When push_settings returns, on_complete has NOT been called yet
        assert.is_false(on_complete_called)

        -- When queued callback fires later:
        queued_finish()
        assert.is_true(on_complete_called)
        assert.is_true(on_complete_success)

        os.remove(dummy_json)
      end
    )
  end)

  describe("pullSettings and pushSettings against real SyncService", function()
    local NetworkMgr = require("ui/network/manager")
    local SyncService = require("apps/cloudstorage/syncservice")
    local DataStorage = require("datastorage")

    local REMOTE = '{"Me":{"settings":{"reader:x":1},"timestamp":"T1"},'
      .. '"Other":{"settings":{"reader:y":2},"timestamp":"T2"}}'
    local STALE = '{"Me":{"settings":{"reader:x":0},"timestamp":"T0"},'
      .. '"Gone":{"settings":{"reader:z":3},"timestamp":"T0"}}'

    local function has(list, s)
      for _, v in ipairs(list) do
        if v == s then
          return true
        end
      end
      return false
    end

    local function with_cloud(remote_code, remote_body, local_body, fn)
      local json_path = DataStorage:getDataDir() .. "/settings_sync.json"
      os.remove(json_path)
      os.remove(json_path .. ".sync")
      if local_body then
        assert(util.writeToFile(local_body, json_path))
      end
      local uploads, shown = {}, {}
      local old_api = package.loaded["apps/cloudstorage/webdavapi"]
      package.loaded["apps/cloudstorage/webdavapi"] = {
        getJoinedPath = function(_, a, b)
          return tostring(a) .. "/" .. tostring(b)
        end,
        downloadFile = function(_, _, _, _, path)
          if remote_code == 200 then
            assert(util.writeToFile(remote_body, path))
          end
          return remote_code, "etag"
        end,
        uploadFile = function(_, _, _, _, file_path)
          table.insert(uploads, util.readFromFile(file_path, "r"))
          return 201
        end,
      }
      local old_rwc, old_show, old_sync =
        NetworkMgr.runWhenConnected, UIManager.show, SyncService.sync
      NetworkMgr.runWhenConnected = function(_, f)
        f()
      end
      SyncService.sync = real_sync
      UIManager.show = function(_, w)
        table.insert(shown, tostring(w.title or w.text))
      end
      local ok, err = pcall(fn)
      NetworkMgr.runWhenConnected, UIManager.show, SyncService.sync =
        old_rwc, old_show, old_sync
      package.loaded["apps/cloudstorage/webdavapi"] = old_api
      assert(ok, err)
      local after = util.fileExists(json_path)
          and util.readFromFile(json_path, "r")
        or nil
      return uploads, shown, after
    end

    before_each(function()
      sync_instance:onSyncServiceConfirm({
        address = "http://test-server-pull",
        url = "/dir",
        type = "webdav",
      })
      sync_instance.settings.device_name = "Me"
    end)

    it("pull: cloud has Me+Other, no local file", function()
      local uploads, shown, after = with_cloud(200, REMOTE, nil, function()
        sync_instance.manager:pullSettings()
      end)
      assert.is_equal(0, #uploads)
      assert.is_true(has(shown, "Pull settings from cloud"))
      assert.is_false(has(shown, "Successfully synchronized."))
      assert.is_nil(after)
    end)

    it("pull: cloud file missing (404), stale local file", function()
      local uploads, shown, after = with_cloud(404, nil, STALE, function()
        sync_instance.manager:pullSettings()
      end)
      assert.is_equal(0, #uploads)
      assert.is_true(has(shown, "No other devices found in cloud settings."))
      assert.is_equal(STALE, after)
    end)

    it("pull: offline, waits for the network instead of refusing", function()
      local old_conn = NetworkMgr.isConnected
      finally(function()
        NetworkMgr.isConnected = old_conn
      end)
      NetworkMgr.isConnected = function()
        return false
      end
      local pending
      local uploads, shown = with_cloud(200, REMOTE, nil, function()
        NetworkMgr.runWhenConnected = function(_, f)
          pending = f
        end
        sync_instance.manager:pullSettings()
        assert.is_function(pending)
        pending()
      end)
      assert.is_equal(0, #uploads)
      assert.is_true(has(shown, "Pull settings from cloud"))
    end)

    it("push: cloud file missing (404), one setting selected", function()
      finally(function()
        G_reader_settings:delete("auto_suspend_timeout_seconds")
      end)
      G_reader_settings:save("auto_suspend_timeout_seconds", 300)
      sync_instance.settings.selected_settings =
        { ["reader:auto_suspend_timeout_seconds"] = true }
      local uploads = with_cloud(404, nil, nil, function()
        sync_instance.manager:pushSettings()
      end)
      assert.is_equal(1, #uploads)
      local data = json.decode(uploads[1])
      assert.is_not_nil(data.Me)
      assert.is_equal(300, data.Me.settings["reader:auto_suspend_timeout_seconds"])
      assert.is_nil(data.Other)
    end)

    it("push: a failed write of the merged file uploads nothing", function()
      local json_path = DataStorage:getDataDir() .. "/settings_sync.json"
      local old_write = util.writeToFile
      finally(function()
        G_reader_settings:delete("auto_suspend_timeout_seconds")
        util.writeToFile = old_write
      end)
      G_reader_settings:save("auto_suspend_timeout_seconds", 300)
      sync_instance.settings.selected_settings =
        { ["reader:auto_suspend_timeout_seconds"] = true }
      -- The file with Other's settings merged in can't be written, e.g.
      -- because the disk is full.
      util.writeToFile = function(data, path, ...)
        if path == json_path and data:find('"Other"', 1, true) then
          return false, "No space left on device"
        end
        return old_write(data, path, ...)
      end

      local uploads, shown = with_cloud(200, REMOTE, nil, function()
        sync_instance.manager:pushSettings()
      end)

      assert.is_equal(0, #uploads)
      assert.is_false(has(shown, "Successfully synchronized."))
      assert.is_true(
        has(
          shown,
          "Something went wrong when syncing, please check your network connection and try again later."
        )
      )
    end)

    it("push: uploads reader setting changed in memory only", function()
      finally(function()
        G_reader_settings:delete("auto_standby_timeout_seconds")
      end)
      -- Saved as 100, then changed to 888 in memory only.
      G_reader_settings:save("auto_standby_timeout_seconds", 100)
      G_reader_settings:flush()
      G_reader_settings:save("auto_standby_timeout_seconds", 888)
      sync_instance.settings.selected_settings =
        { ["reader:auto_standby_timeout_seconds"] = true }

      local uploads = with_cloud(200, REMOTE, nil, function()
        sync_instance.manager:pushSettings()
      end)

      assert.is_equal(1, #uploads)
      local data = json.decode(uploads[1])
      assert.is_not_nil(data.Me)
      assert.is_equal(888, data.Me.settings["reader:auto_standby_timeout_seconds"])
    end)
  end)

  describe("settings pull menus keep open during interaction", function()
    local logger = require("logger")
    local menus = require("plugins/AnnotationSync.koplugin/menus")

    it(
      "devices menu and differing settings menu stay open on selection, and import closes cleanly",
      function()
        local settings_map = {
          ["OtherDevice"] = {
            timestamp = "2026-10-08",
            settings = {
              ["reader:auto_standby_timeout_seconds"] = 999,
              ["reader:auto_suspend_timeout_seconds"] = 888,
            },
          },
        }

        local shown_menus = {}
        local old_show = UIManager.show
        finally(function()
          G_reader_settings:delete("auto_standby_timeout_seconds")
          G_reader_settings:delete("auto_suspend_timeout_seconds")
          UIManager.show = old_show
          for _, m in ipairs(shown_menus) do
            UIManager:closeIfShown(m)
          end
        end)
        G_reader_settings:save("auto_standby_timeout_seconds", 100)
        G_reader_settings:save("auto_suspend_timeout_seconds", 200)
        UIManager.show = function(this, widget)
          if widget.item_table then
            table.insert(shown_menus, widget)
          end
          return old_show(this, widget)
        end

        menus.show_devices_menu(sync_instance, settings_map)
        local devices_menu = shown_menus[1]
        assert.is_not_nil(devices_menu)
        assert.is_true(UIManager:isWindowWidget(devices_menu))

        devices_menu:onMenuSelect(devices_menu.item_table[1])
        assert.is_true(UIManager:isWindowWidget(devices_menu))
        local diff_menu = shown_menus[2]
        assert.is_not_nil(diff_menu)
        assert.is_true(UIManager:isWindowWidget(diff_menu))

        local import_item, select_all_item, clear_selection_item, setting_item
        for _, item in ipairs(diff_menu.item_table) do
          if item.text == "Import Selected Settings" then
            import_item = item
          elseif item.text == "Select All" then
            select_all_item = item
          elseif item.text == "Clear Selection" then
            clear_selection_item = item
          elseif item.text_func then
            setting_item = item
          end
        end
        assert.is_not_nil(import_item)
        assert.is_not_nil(select_all_item)
        assert.is_not_nil(clear_selection_item)
        assert.is_not_nil(setting_item)

        assert.is_truthy(setting_item.text_func():find("%[✓%]"))
        diff_menu:onMenuSelect(setting_item)
        assert.is_true(UIManager:isWindowWidget(diff_menu))
        assert.is_truthy(setting_item.text_func():find("%[ %]"))

        diff_menu:onMenuSelect(clear_selection_item)
        assert.is_true(UIManager:isWindowWidget(diff_menu))
        assert.is_truthy(setting_item.text_func():find("%[ %]"))

        diff_menu:onMenuSelect(select_all_item)
        assert.is_true(UIManager:isWindowWidget(diff_menu))
        assert.is_truthy(setting_item.text_func():find("%[✓%]"))

        local warnings = {}
        local old_warn = logger.warn
        finally(function()
          logger.warn = old_warn
        end)
        logger.warn = function(...)
          local msg = table.concat({ ... }, " ")
          table.insert(warnings, msg)
          return old_warn(...)
        end

        diff_menu:onMenuSelect(import_item)
        assert.is_false(UIManager:isWindowWidget(diff_menu))
        assert.is_false(UIManager:isWindowWidget(devices_menu))

        for _, w in ipairs(warnings) do
          assert.is_nil(w:find("has been closed already"))
        end
      end
    )
  end)
end)
