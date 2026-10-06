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
    -- Mock active reader settings
    local f = io.open(test_data_dir .. "/settings.reader.lua", "w")
    f:write([[
return {
    ["auto_standby_timeout_seconds"] = 120,
    ["footer"] = {
        ["time"] = true
    }
}
]])
    f:close()

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
    "should correctly write local file and sync it using remote.push_settings",
    function()
      -- Configure mock sync server
      local test_server =
        { url = "http://test-server-settings", type = "webdav" }
      sync_instance:onSyncServiceConfirm(test_server)

      -- Mock active settings
      local f = io.open(test_data_dir .. "/settings.reader.lua", "w")
      f:write([[
return {
    ["auto_suspend_timeout_seconds"] = 300
}
]])
      f:close()

      -- Select the setting
      sync_instance.settings.selected_settings = {
        ["reader:auto_suspend_timeout_seconds"] = true,
      }

      -- Set custom device name
      sync_instance.settings.device_name = "TestDeviceX"

      -- Mock SyncService to assert the values being synced
      local sync_called = false
      local remote_file_content = nil

      local SyncService = require("apps/cloudstorage/syncservice")
      local old_sync = SyncService.sync
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

      -- Restore mock
      SyncService.sync = old_sync

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

      -- Mock active reader settings on local device
      local f = io.open(test_data_dir .. "/settings.reader.lua", "w")
      f:write([[
return {
    ["auto_suspend_timeout_seconds"] = 300,
    ["auto_standby_timeout_seconds"] = 100
}
]])
      f:close()

      -- Mock SyncService to simulate pulling other devices' settings
      local sync_called = false
      local SyncService = require("apps/cloudstorage/syncservice")
      local old_sync = SyncService.sync
      local old_show = UIManager.show
      finally(function()
        SyncService.sync = old_sync
        UIManager.show = old_show
      end)
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
      local local_lines = { "return {" }
      local remote_json_parts = { "{" }
      for m = 1, 100 do
        local map_name = ("map_%03d"):format(m)
        table.insert(local_lines, ('  ["%s"] = {'):format(map_name))
        table.insert(
          remote_json_parts,
          (m > 1 and ',"reader:%s":{' or '"reader:%s":{'):format(map_name)
        )
        for i = 1, 32 do
          local k = ("m%03d_k%02d"):format(m, i)
          table.insert(local_lines, ('    ["%s"] = true,'):format(k))
        end
        table.insert(local_lines, "  },")
        for i = 32, 1, -1 do
          local k = ("m%03d_k%02d"):format(m, i)
          table.insert(
            remote_json_parts,
            (i < 32 and ',"%s":true' or '"%s":true'):format(k)
          )
        end
        table.insert(remote_json_parts, "}")
      end
      table.insert(local_lines, "}")
      table.insert(remote_json_parts, "}")

      local f = io.open(test_data_dir .. "/settings.reader.lua", "w")
      f:write(table.concat(local_lines, "\n"))
      f:close()

      local remote_settings = json.decode(table.concat(remote_json_parts))

      local shown = {}
      local old_show = UIManager.show
      finally(function()
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

  describe("remote.sync_settings finish_cb contract", function()
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
      "Case 18: sync_settings: on_complete is called only from finish_cb; postponed calls it later",
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
        remote.sync_settings(sync_instance, dummy_json, function(success)
          on_complete_called = true
          on_complete_success = success
        end)

        -- When sync_settings returns, on_complete has NOT been called yet
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
      local f = io.open(test_data_dir .. "/settings.reader.lua", "w")
      f:write('return { ["auto_suspend_timeout_seconds"] = 300 }')
      f:close()
      sync_instance.settings.selected_settings =
        { ["reader:auto_suspend_timeout_seconds"] = true }
      local uploads, shown = with_cloud(404, nil, nil, function()
        sync_instance.manager:pushSettings()
      end)
      assert.is_equal(1, #uploads)
      local data = json.decode(uploads[1])
      assert.is_not_nil(data.Me)
      assert.is_equal(300, data.Me.settings["reader:auto_suspend_timeout_seconds"])
      assert.is_nil(data.Other)
    end)
  end)
end)
