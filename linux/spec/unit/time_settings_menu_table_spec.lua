describe("time_settings_menu_table module", function()
  local time_menu
  local UIManager
  local Device

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    Device = require("device")
    time_menu = require("ui/elements/time_settings_menu_table")
  end)

  it("should export menu structure with sub items", function()
    assert.is_table(time_menu)
    assert.is_string(time_menu.text)
    assert.is_table(time_menu.sub_item_table)
  end)

  it("should handle 12-hour clock toggles and event broadcast", function()
    local item_12h = time_menu.sub_item_table[1]
    assert.is_not_nil(item_12h)
    assert.is_function(item_12h.checked_func)

    local broadcasted
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      broadcasted = ev
    end

    local prev = item_12h.checked_func()
    item_12h.callback()
    assert.are.equal("TimeFormatChanged", broadcasted)
    assert.are_not_equal(prev, item_12h.checked_func())

    item_12h.callback()
    assert.are.equal(prev, item_12h.checked_func())

    UIManager.broadcastEvent = orig_broadcast
  end)

  it("should handle duration format options and text generation", function()
    local item_duration = time_menu.sub_item_table[2]
    assert.is_not_nil(item_duration)
    assert.is_function(item_duration.text_func)
    assert.is_table(item_duration.sub_item_table)

    local broadcasted
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      broadcasted = ev
    end

    -- Sub items: classic, modern, letters
    local sub_items = item_duration.sub_item_table
    assert.are.equal(3, #sub_items)

    -- Classic
    assert.is_string(sub_items[1].text_func())
    sub_items[1].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[1].checked_func())
    assert.is_false(sub_items[2].checked_func())
    assert.is_false(sub_items[3].checked_func())
    assert.is_true(item_duration.text_func():find("Classic") ~= nil)

    -- Modern
    assert.is_string(sub_items[2].text_func())
    sub_items[2].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[2].checked_func())
    assert.is_false(sub_items[1].checked_func())
    assert.is_true(item_duration.text_func():find("Modern") ~= nil)

    -- Letters
    assert.is_string(sub_items[3].text_func())
    sub_items[3].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[3].checked_func())
    assert.is_false(sub_items[2].checked_func())
    assert.is_true(item_duration.text_func():find("Letters") ~= nil)

    UIManager.broadcastEvent = orig_broadcast
  end)

  it("should handle Set time and Set date dialogs when supported", function()
    local orig_set_dt = Device.setDateTime
    Device.setDateTime = function()
      return true
    end

    package.loaded["ui/elements/time_settings_menu_table"] = nil
    local custom_menu = require("ui/elements/time_settings_menu_table")

    local item_time, item_date
    for _, item in ipairs(custom_menu.sub_item_table) do
      if item.text == "Set time" then
        item_time = item
      elseif item.text == "Set date" then
        item_date = item
      end
    end

    assert.is_not_nil(item_time)
    assert.is_not_nil(item_date)

    local shown_widget
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    -- Test Set time callback
    item_time.callback()
    local time_dialog = shown_widget
    assert.is_not_nil(time_dialog)
    assert.is_function(time_dialog.callback)
    time_dialog.callback({ hour = 10, min = 30 })

    -- Test failure case of Set time
    Device.setDateTime = function(self, y, m, d, h, min)
      if h then
        return false
      end
      return true
    end
    time_dialog.callback({ hour = 10, min = 30 })

    -- Test Set date callback
    item_date.callback()
    local date_dialog = shown_widget
    assert.is_not_nil(date_dialog)
    assert.is_function(date_dialog.callback)
    Device.setDateTime = function()
      return true
    end
    date_dialog.callback({ year = 2026, month = 8, day = 24 })

    -- Test failure case of Set date
    Device.setDateTime = function()
      return false
    end
    date_dialog.callback({ year = 2026, month = 8, day = 24 })

    UIManager.show = orig_show
    Device.setDateTime = orig_set_dt
    package.loaded["ui/elements/time_settings_menu_table"] = nil
  end)

  it("handles capability detection and registration in add_sync_time", function()
    local ffi = require("ffi")
    local lfs = require("libs/libkoreader-lfs")
    local BackgroundJobs = require("background_jobs")
    local original_ffi_C = ffi.C
    local orig_symlinkattributes = lfs.symlinkattributes
    local mock_uid = 1000

    local mock_C = setmetatable({
      getuid = function()
        return mock_uid
      end,
    }, {
      __index = original_ffi_C,
    })

    local mock_ffi = setmetatable({
      C = mock_C,
    }, {
      __index = ffi,
    })

    package.loaded["ffi"] = mock_ffi

    local inserted_jobs = {}
    local orig_insert = BackgroundJobs.insert
    BackgroundJobs.insert = function(job)
      table.insert(inserted_jobs, job)
    end

    local exec_stub = stub(os, "execute", function(cmd)
      if cmd == "command -v ntpd >/dev/null" then
        return 0
      end
      return 1
    end)

    finally(function()
      package.loaded["ffi"] = ffi
      exec_stub:revert()
      lfs.symlinkattributes = orig_symlinkattributes
      BackgroundJobs.insert = orig_insert
      package.loaded["ui/elements/time_settings_menu_table"] = nil
    end)

    -- Case 1: non-root user (uid ~= 0) -> no sync items, no idle job
    mock_uid = 1000
    inserted_jobs = {}
    package.loaded["ui/elements/time_settings_menu_table"] = nil
    local custom_menu = require("ui/elements/time_settings_menu_table")
    assert.are.equal(0, #inserted_jobs)

    -- Case 2: root user with busybox ntpd -> registers idle job and exposes syncNTPOnly
    mock_uid = 0
    lfs.symlinkattributes = function(path)
      if path:match("ntpd$") then
        return { mode = "link", target = "/bin/busybox" }
      end
      return nil
    end

    inserted_jobs = {}
    package.loaded["ui/elements/time_settings_menu_table"] = nil
    custom_menu = require("ui/elements/time_settings_menu_table")
    assert.are.equal(1, #inserted_jobs)
    assert.are.equal("idle", inserted_jobs[1].when)
    assert.is_true(inserted_jobs[1].repeated)

    -- Case 3: root user with ntpdate (no busybox ntpd) -> registers idle job
    lfs.symlinkattributes = function()
      return nil
    end
    exec_stub.invokes(function(cmd)
      if cmd == "command -v ntpdate >/dev/null" then
        return 0
      end
      return 1
    end)

    inserted_jobs = {}
    package.loaded["ui/elements/time_settings_menu_table"] = nil
    custom_menu = require("ui/elements/time_settings_menu_table")
    assert.are.equal(1, #inserted_jobs)

    -- Case 4: root user but neither ntpd nor ntpdate available -> returns early
    exec_stub.invokes(function()
      return 1
    end)

    inserted_jobs = {}
    package.loaded["ui/elements/time_settings_menu_table"] = nil
    custom_menu = require("ui/elements/time_settings_menu_table")
    assert.are.equal(0, #inserted_jobs)
  end)

  it("handles syncNTPOnly command execution on failure and success", function()
    local ffi = require("ffi")
    local lfs = require("libs/libkoreader-lfs")
    local gettext = require("gettext")
    local BackgroundJobs = require("background_jobs")
    local NetworkMgr = require("ui/network/manager")
    local original_ffi_C = ffi.C
    local orig_symlinkattributes = lfs.symlinkattributes
    local orig_attributes = lfs.attributes
    local orig_insert = BackgroundJobs.insert
    local orig_insertKeyed = BackgroundJobs.insertKeyed

    local mock_C = setmetatable({
      getuid = function()
        return 0
      end,
    }, {
      __index = original_ffi_C,
    })

    local mock_ffi = setmetatable({
      C = mock_C,
    }, {
      __index = ffi,
    })

    package.loaded["ffi"] = mock_ffi
    lfs.symlinkattributes = function()
      return nil
    end

    local registered_idle_job = nil
    local syncNTPOnly = nil
    BackgroundJobs.insert = function(job)
      if job.when == "idle" then
        registered_idle_job = job
      end
    end
    BackgroundJobs.insertKeyed = function(job)
      syncNTPOnly = job.action
    end

    local executed_cmds = {}
    local exec_stub = stub(os, "execute", function(cmd)
      table.insert(executed_cmds, cmd)
      if cmd == "command -v ntpdate >/dev/null" then
        return 0
      end
      if cmd == "ntpdate pool.ntp.org" then
        return 1
      end
      return 0
    end)
    stub(Device, "isKindle").returns(false)
    stub(NetworkMgr, "isOnline").returns(true)
    G_reader_settings:save("auto_sync_time", true)

    finally(function()
      package.loaded["ffi"] = ffi
      exec_stub:revert()
      Device.isKindle:revert()
      NetworkMgr.isOnline:revert()
      lfs.symlinkattributes = orig_symlinkattributes
      lfs.attributes = orig_attributes
      BackgroundJobs.insert = orig_insert
      BackgroundJobs.insertKeyed = orig_insertKeyed
      G_reader_settings:delete("auto_sync_time")
      package.loaded["ui/elements/time_settings_menu_table"] = nil
    end)

    package.loaded["ui/elements/time_settings_menu_table"] = nil
    require("ui/elements/time_settings_menu_table")

    assert.is_not_nil(registered_idle_job)
    registered_idle_job.executable()
    assert.is_function(syncNTPOnly)

    -- Failure when NTP command exits with non-zero
    executed_cmds = {}
    local txt = syncNTPOnly()
    assert.are.equal(
      gettext(
        "Failed to retrieve time from server. Please check your network configuration."
      ),
      txt
    )
    assert.are.equal(1, #executed_cmds)
    assert.are.equal("ntpdate pool.ntp.org", executed_cmds[1])

    -- Success executes hwclock and returns formatted time
    executed_cmds = {}
    exec_stub.invokes(function(cmd)
      table.insert(executed_cmds, cmd)
      return 0
    end)

    txt = syncNTPOnly()
    assert.is_string(txt)
    assert.are.equal("ntpdate pool.ntp.org", executed_cmds[1])
    assert.are.equal("hwclock -u -w", executed_cmds[2])

    -- Success on Kindle executes /usr/sbin/setdate if file exists
    executed_cmds = {}
    Device.isKindle.returns(true)
    lfs.attributes = function(path, req)
      if path == "/usr/sbin/setdate" and req == "mode" then
        return "file"
      end
      return orig_attributes(path, req)
    end

    txt = syncNTPOnly()
    assert.is_string(txt)
    local found_setdate = false
    for _, cmd in ipairs(executed_cmds) do
      if cmd:find("^/usr/sbin/setdate") then
        found_setdate = true
        break
      end
    end
    assert.is_true(found_setdate)
  end)

  it("handles menu items and syncNTP with UI feedback", function()
    local ffi = require("ffi")
    local NetworkMgr = require("ui/network/manager")
    local BackgroundJobs = require("background_jobs")
    local gettext = require("gettext")
    local original_ffi_C = ffi.C

    local mock_C = setmetatable({
      getuid = function()
        return 0
      end,
    }, {
      __index = original_ffi_C,
    })

    local mock_ffi = setmetatable({
      C = mock_C,
    }, {
      __index = ffi,
    })

    package.loaded["ffi"] = mock_ffi

    local exec_stub = stub(os, "execute", function(cmd)
      if cmd == "command -v ntpdate >/dev/null" then
        return 0
      end
      return 0
    end)

    local run_when_online_stub = stub(NetworkMgr, "runWhenOnline", function(self, cb)
      cb()
    end)

    local run_with_called = false
    local orig_runWith = UIManager.runWith
    UIManager.runWith = function(self, func, msg)
      run_with_called = true
      assert.are.equal(
        gettext("Synchronizing time. This may take several seconds."),
        msg
      )
      func()
    end

    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end

    local registered_idle_job = nil
    local orig_insert = BackgroundJobs.insert
    local insert_keyed_stub = stub(BackgroundJobs, "insertKeyed")
    BackgroundJobs.insert = function(job)
      if job.when == "idle" then
        registered_idle_job = job
      end
    end

    G_reader_settings:delete("auto_sync_time")

    finally(function()
      package.loaded["ffi"] = ffi
      exec_stub:revert()
      run_when_online_stub:revert()
      insert_keyed_stub:revert()
      BackgroundJobs.insert = orig_insert
      UIManager.runWith = orig_runWith
      UIManager.show = orig_show
      G_reader_settings:delete("auto_sync_time")
      package.loaded["ui/elements/time_settings_menu_table"] = nil
    end)

    package.loaded["ui/elements/time_settings_menu_table"] = nil
    local custom_menu = require("ui/elements/time_settings_menu_table")

    local auto_item
    for _, item in ipairs(custom_menu.sub_item_table) do
      if item.text == gettext("Automatically synchronize time") then
        auto_item = item
        break
      end
    end

    assert.is_not_nil(auto_item)
    assert.is_false(auto_item.checked_func())

    -- Toggle auto_sync_time to true -> triggers runWhenOnline and syncNTP
    auto_item.callback()
    assert.is_true(G_reader_settings:isTrue("auto_sync_time"))
    assert.is_true(auto_item.checked_func())
    assert.stub(run_when_online_stub).was_called(1)
    assert.is_true(run_with_called)
    assert.is_not_nil(shown_widget)
    assert.are.equal(3, shown_widget.timeout)

    -- In-memory last_sync_time updated; subsequent idle check does not re-sync
    assert.is_not_nil(registered_idle_job)
    registered_idle_job.executable()
    assert.stub(insert_keyed_stub).was_not_called()

    -- Toggle auto_sync_time to false -> does not trigger sync
    run_with_called = false
    run_when_online_stub:clear()
    auto_item.callback()
    assert.is_false(G_reader_settings:isTrue("auto_sync_time"))
    assert.is_false(auto_item.checked_func())
    assert.stub(run_when_online_stub).was_not_called()
    assert.is_false(run_with_called)
  end)

  it("handles idle job 24h cooldown and background fork execution", function()
    local MockTime = require("mock_time")
    MockTime:install()

    local ffi = require("ffi")
    local BackgroundJobs = require("background_jobs")
    local NetworkMgr = require("ui/network/manager")
    local original_ffi_C = ffi.C

    local mock_C = setmetatable({
      getuid = function()
        return 0
      end,
    }, {
      __index = original_ffi_C,
    })

    local mock_ffi = setmetatable({
      C = mock_C,
    }, {
      __index = ffi,
    })

    package.loaded["ffi"] = mock_ffi

    local exec_stub = stub(os, "execute", function(cmd)
      if cmd == "command -v ntpdate >/dev/null" then
        return 0
      end
      return 0
    end)

    local registered_idle_job = nil
    local orig_insert = BackgroundJobs.insert
    BackgroundJobs.insert = function(job)
      if job.when == "idle" then
        registered_idle_job = job
      end
    end

    local insert_stub = stub(BackgroundJobs, "insertKeyed")
    stub(NetworkMgr, "isOnline").returns(true)

    G_reader_settings:delete("auto_sync_time")

    finally(function()
      MockTime:uninstall()
      package.loaded["ffi"] = ffi
      exec_stub:revert()
      insert_stub:revert()
      NetworkMgr.isOnline:revert()
      BackgroundJobs.insert = orig_insert
      G_reader_settings:delete("auto_sync_time")
      package.loaded["ui/elements/time_settings_menu_table"] = nil
    end)

    package.loaded["ui/elements/time_settings_menu_table"] = nil
    require("ui/elements/time_settings_menu_table")

    assert.is_not_nil(registered_idle_job)
    assert.is_function(registered_idle_job.executable)
    local idle_fn = registered_idle_job.executable

    -- 1. Does nothing if auto_sync_time is false/nil
    idle_fn()
    assert.stub(insert_stub).was_not_called()

    -- 2. Does nothing if network is offline
    G_reader_settings:save("auto_sync_time", true)
    NetworkMgr.isOnline.returns(false)
    idle_fn()
    assert.stub(insert_stub).was_not_called()

    -- 3. Enqueues fork job when conditions met (online and no previous sync)
    NetworkMgr.isOnline.returns(true)
    local captured_job = nil
    insert_stub.invokes(function(job)
      captured_job = job
      return true
    end)

    idle_fn()
    assert.is_not_nil(captured_job)
    assert.are.equal("fork", captured_job.executable)
    assert.is_function(captured_job.action)
    assert.is_function(captured_job.callback)

    -- 4. Callback records last_sync_time in memory; subsequent idle check within 24h does not re-sync
    captured_job.callback({ result = "New time is 12:00." })
    insert_stub:clear()

    idle_fn()
    assert.stub(insert_stub).was_not_called()

    -- 5. Does nothing after 1 hour (< 86400s)
    MockTime:increase(3600)
    idle_fn()
    assert.stub(insert_stub).was_not_called()

    -- 6. Re-enqueues fork job after 24 hours have elapsed
    MockTime:increase(86400 - 3600 + 1)
    idle_fn()
    assert.stub(insert_stub).was_called(1)
  end)
end)
