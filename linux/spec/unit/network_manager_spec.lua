-- luacheck: ignore 122
describe("network_manager module", function()
  local Device
  local UIManager
  local turn_on_wifi_called
  local turn_off_wifi_called
  local obtain_ip_called
  local release_ip_called

  local function clearState()
    G_reader_settings:save("auto_restore_wifi", true)
    turn_on_wifi_called = 0
    turn_off_wifi_called = 0
    obtain_ip_called = 0
    release_ip_called = 0
  end

  setup(function()
    require("commonrequire")
    Device = require("device")
    UIManager = require("ui/uimanager")
    function Device:initNetworkManager(NetworkMgr)
      function NetworkMgr:turnOnWifi(callback)
        turn_on_wifi_called = turn_on_wifi_called + 1
        if callback then
          callback()
        end
      end
      function NetworkMgr:turnOffWifi(callback)
        turn_off_wifi_called = turn_off_wifi_called + 1
        if callback then
          callback()
        end
      end
      function NetworkMgr:obtainIP(callback)
        obtain_ip_called = obtain_ip_called + 1
        if callback then
          callback()
        end
      end
      function NetworkMgr:releaseIP(callback)
        release_ip_called = release_ip_called + 1
        if callback then
          callback()
        end
      end
      function NetworkMgr:restoreWifiAsync()
        self:turnOnWifi()
        self:obtainIP()
      end
    end
    function Device:hasWifiRestore()
      return true
    end
  end)

  it("should restore wifi in init if wifi was on", function()
    package.loaded["ui/network/manager"] = nil
    clearState()
    G_reader_settings:save("wifi_was_on", true)
    local network_manager = require("ui/network/manager") --luacheck: ignore
    UIManager:_checkTasks()
    assert.is.same(turn_on_wifi_called, 1)
    assert.is.same(turn_off_wifi_called, 0)
    assert.is.same(obtain_ip_called, 1)
    assert.is.same(release_ip_called, 0)
  end)

  it("should not restore wifi in init if auto_restore_wifi is off", function()
    package.loaded["ui/network/manager"] = nil
    clearState()
    G_reader_settings:save("auto_restore_wifi", false)
    local network_manager = require("ui/network/manager") --luacheck: ignore
    UIManager:_checkTasks()
    assert.is.same(turn_on_wifi_called, 0)
    assert.is.same(turn_off_wifi_called, 0)
    assert.is.same(obtain_ip_called, 0)
    assert.is.same(release_ip_called, 0)
  end)

  describe("ConnectivityChecker", function()
    local NetworkMgr
    local Checker
    local original_isWifiConnected
    local original_networkConnected
    local original_abortWifiConnection
    local original_show
    local original_clock
    local abort_called
    local connected_called
    local show_called
    local shown_message
    local current_time

    setup(function()
      -- Load the module
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
      Checker = NetworkMgr.ConnectivityChecker

      -- Save original methods
      original_isWifiConnected = NetworkMgr._isWifiConnected
      original_networkConnected = NetworkMgr._networkConnected
      original_abortWifiConnection = NetworkMgr._abortWifiConnection
      original_show = UIManager.show
      original_clock = os.clock
    end)

    before_each(function()
      abort_called = 0
      connected_called = 0
      show_called = 0
      shown_message = nil
      current_time = 100

      -- Mock methods
      NetworkMgr._isWifiConnected = function()
        return false
      end
      NetworkMgr._networkConnected = function()
        connected_called = connected_called + 1
      end
      NetworkMgr._abortWifiConnection = function()
        abort_called = abort_called + 1
      end
      UIManager.show = function(_self_ui, widget)
        show_called = show_called + 1
        shown_message = widget
      end
      os.clock = function()
        return current_time
      end

      Checker:stop()
    end)

    after_each(function()
      Checker:stop()
    end)

    teardown(function()
      -- Restore original methods
      NetworkMgr._isWifiConnected = original_isWifiConnected
      NetworkMgr._networkConnected = original_networkConnected
      NetworkMgr._abortWifiConnection = original_abortWifiConnection
      UIManager.show = original_show
      os.clock = original_clock
    end)

    it("should not be running initially", function()
      assert.is_false(Checker:running())
    end)

    it("should start and stop correctly", function()
      Checker:start()
      assert.is_true(Checker:running())
      assert.is_nil(Checker.interactive)

      Checker:stop()
      assert.is_false(Checker:running())
    end)

    it("should start with interactive flag", function()
      Checker:start(true)
      assert.is_true(Checker:running())
      assert.is_true(Checker.interactive)
    end)

    it("should do nothing on execution if not running", function()
      Checker:executable()
      assert.is.same(connected_called, 0)
      assert.is.same(abort_called, 0)
      assert.is.same(show_called, 0)
    end)

    it("should restore network on execution if wifi is connected", function()
      NetworkMgr._isWifiConnected = function()
        return true
      end
      Checker:start()
      Checker:executable()

      -- nextTick is asynchronous, so we must run UIManager tasks
      UIManager:_checkTasks()

      assert.is.same(connected_called, 1)
      assert.is_false(Checker:running())
      assert.is.same(abort_called, 0)
    end)

    it(
      "should do nothing on execution if not connected and within 60s",
      function()
        Checker:start()
        current_time = 110 -- 10 seconds elapsed

        Checker:executable()

        assert.is.same(connected_called, 0)
        assert.is.same(abort_called, 0)
        assert.is.same(show_called, 0)
        assert.is_true(Checker:running())
      end
    )

    it(
      "should abort connection on execution if not connected after 60s (non-interactive)",
      function()
        Checker:start(false)
        current_time = 161 -- 61 seconds elapsed

        Checker:executable()

        assert.is.same(connected_called, 0)
        assert.is.same(abort_called, 1)
        assert.is.same(show_called, 0)
        assert.is_false(Checker:running())
      end
    )

    it(
      "should abort connection and show warning on execution if not connected after 60s (interactive)",
      function()
        Checker:start(true)
        current_time = 161 -- 61 seconds elapsed

        Checker:executable()

        assert.is.same(connected_called, 0)
        assert.is.same(abort_called, 1)
        assert.is.same(show_called, 1)
        assert.is_not_nil(shown_message)
        assert.is_false(Checker:running())
      end
    )
  end)

  describe("ConnectivityChecker background fork job", function()
    it(
      "should update online state when background fork job queries _returnOnlineState",
      function()
        local NetworkMgr = require("ui/network/manager")
        local orig_wait = Device.input.waitEvent
        Device.input.waitEvent = function() end

        local orig_runForever = UIManager._run_forever
        UIManager:setRunForeverMode()

        local MockTime = require("mock_time")
        MockTime:install()

        local BackgroundRunnerWidget = requireBackgroundRunner()
        BackgroundRunnerWidget:init()
        BackgroundRunnerWidget:allowBlockingJobs(true)

        local PluginShare = require("pluginshare")
        PluginShare.stopBackgroundRunner = false
        NetworkMgr.last_online_check_time = 0
        NetworkMgr.was_online = nil

        local mock_online = true
        NetworkMgr._returnOnlineState = function()
          return mock_online
        end

        local callback_count = 0
        require("background_jobs").insert({
          when = 1,
          repeated = 2,
          executable = "fork",
          action = function()
            return NetworkMgr:_returnOnlineState()
          end,
          callback = function(job)
            NetworkMgr:_setOnlineState(job.result == true, job.start_time)
            callback_count = callback_count + 1
          end,
        })
        notifyBackgroundJobsUpdated()

        local ffi = require("ffi")
        while callback_count < 1 do
          ffi.C.poll(nil, 0, 50)
          MockTime:increase(2)
          UIManager:handleInput()
        end

        assert.is_true(NetworkMgr.was_online)

        mock_online = false
        NetworkMgr.last_online_check_time = 0

        while callback_count < 2 do
          ffi.C.poll(nil, 0, 50)
          MockTime:increase(2)
          UIManager:handleInput()
        end

        assert.is_false(NetworkMgr.was_online)
        MockTime:uninstall()
        UIManager._run_forever = orig_runForever
        stopBackgroundRunner()
        Device.input.waitEvent = orig_wait
      end
    )
  end)

  describe("reconnect and showNetworkMenu", function()
    local NetworkMgr
    local network_connected_called
    local original_networkConnected

    setup(function()
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
      original_networkConnected = NetworkMgr._networkConnected
      NetworkMgr._networkConnected = function(self)
        network_connected_called = network_connected_called + 1
      end
    end)

    before_each(function()
      network_connected_called = 0
      -- Mock getNetworkList to return a mocked list
      NetworkMgr.getNetworkList = function()
        return {
          {
            ssid = "MockAP",
            signal_quality = 100,
            connected = true,
            flags = "WPA",
          },
        }
      end
    end)

    it(
      "should call _networkConnected when reconnect succeeds (auto-connect path)",
      function()
        local callback_ran = false
        local res = NetworkMgr:reconnect(function()
          callback_ran = true
        end, false)

        assert.is_true(res)
        assert.is_true(callback_ran)
        assert.is.same(network_connected_called, 1)
      end
    )

    it(
      "should call _networkConnected when showNetworkMenu is connected manually",
      function()
        local callback_ran = false
        local original_show = UIManager.show
        -- Mock UIManager.show to simulate connecting successfully from the network settings widget
        UIManager.show = function(_self_ui, widget)
          if widget.connect_callback then
            widget.connect_callback()
          end
        end

        local res = NetworkMgr:showNetworkMenu(function()
          callback_ran = true
        end)

        assert.is_true(res)
        assert.is_true(callback_ran)
        assert.is.same(network_connected_called, 1)

        UIManager.show = original_show
      end
    )

    teardown(function()
      NetworkMgr._networkConnected = original_networkConnected
    end)
  end)

  describe("runWhenOnline and _beforeWifiAction", function()
    local NetworkMgr
    local original_show
    local show_called_widgets
    local original_isOnline
    local original_isWifiConnected

    setup(function()
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
      original_show = UIManager.show
      original_isOnline = NetworkMgr.isOnline
      original_isWifiConnected = NetworkMgr._isWifiConnected
    end)

    before_each(function()
      show_called_widgets = {}
      UIManager.show = function(_self_ui, widget)
        table.insert(show_called_widgets, widget)
        return widget
      end
    end)

    it(
      "should return false and prompt to select another Wi-Fi if already connected but offline",
      function()
        -- Mock connected but offline state
        NetworkMgr._isWifiConnected = function()
          return true
        end
        NetworkMgr.isOnline = function()
          return false
        end

        local show_network_menu_called = false
        NetworkMgr.showNetworkMenu = function()
          show_network_menu_called = true
        end

        local callback_ran = false
        local res = NetworkMgr:runWhenOnline(function()
          callback_ran = true
        end)

        -- Assert the action was backlogged (runWhenOnline returned false)
        assert.is_false(res)
        assert.is_false(callback_ran)

        local confirm_box = nil
        for _, widget in ipairs(show_called_widgets) do
          if
            widget.ok_text and widget.ok_text:find("Select Wi-Fi", 1, true)
          then
            confirm_box = widget
          end
        end
        assert.is_not_nil(confirm_box)

        -- Simulate clicking "Select Wi-Fi"
        confirm_box.ok_callback()
        assert.is_true(show_network_menu_called)
      end
    )

    teardown(function()
      UIManager.show = original_show
      NetworkMgr.isOnline = original_isOnline
      NetworkMgr._isWifiConnected = original_isWifiConnected
    end)
  end)

  describe("queryOnlineState and _returnOnlineState", function()
    local NetworkMgr

    setup(function()
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
    end)

    it(
      "should return true in _returnOnlineState when hasWifiToggle is false and network is online",
      function()
        local orig_hasWifiToggle = Device.hasWifiToggle
        Device.hasWifiToggle = function()
          return false
        end

        local orig_hasDefaultRoute = NetworkMgr._hasDefaultRoute
        local orig_canResolve = NetworkMgr._canResolveHostnames
        NetworkMgr._hasDefaultRoute = function()
          return true
        end
        NetworkMgr._canResolveHostnames = function()
          return true
        end

        assert.is_true(NetworkMgr:_returnOnlineState())

        NetworkMgr._hasDefaultRoute = orig_hasDefaultRoute
        NetworkMgr._canResolveHostnames = orig_canResolve
        Device.hasWifiToggle = orig_hasWifiToggle
      end
    )

    it(
      "should return false in _returnOnlineState when hasWifiToggle is false and route or DNS fails",
      function()
        local orig_hasWifiToggle = Device.hasWifiToggle
        Device.hasWifiToggle = function()
          return false
        end

        local orig_hasDefaultRoute = NetworkMgr._hasDefaultRoute
        local orig_canResolve = NetworkMgr._canResolveHostnames
        NetworkMgr._hasDefaultRoute = function()
          return false
        end
        NetworkMgr._canResolveHostnames = function()
          return false
        end

        assert.is_false(NetworkMgr:_returnOnlineState())

        NetworkMgr._hasDefaultRoute = orig_hasDefaultRoute
        NetworkMgr._canResolveHostnames = orig_canResolve
        Device.hasWifiToggle = orig_hasWifiToggle
      end
    )

    it(
      "should return false in _returnOnlineState when hasWifiToggle is true and wifi is disconnected",
      function()
        local orig_hasWifiToggle = Device.hasWifiToggle
        Device.hasWifiToggle = function()
          return true
        end

        local orig_isWifiConnected = NetworkMgr._isWifiConnected
        NetworkMgr._isWifiConnected = function()
          return false
        end

        assert.is_false(NetworkMgr:_returnOnlineState())

        NetworkMgr._isWifiConnected = orig_isWifiConnected
        Device.hasWifiToggle = orig_hasWifiToggle
      end
    )

    it(
      "should return true in _returnOnlineState when hasWifiToggle is true, wifi is connected, and network is online",
      function()
        local orig_hasWifiToggle = Device.hasWifiToggle
        Device.hasWifiToggle = function()
          return true
        end

        local orig_isWifiConnected = NetworkMgr._isWifiConnected
        local orig_hasDefaultRoute = NetworkMgr._hasDefaultRoute
        local orig_canResolve = NetworkMgr._canResolveHostnames

        NetworkMgr._isWifiConnected = function()
          return true
        end
        NetworkMgr._hasDefaultRoute = function()
          return true
        end
        NetworkMgr._canResolveHostnames = function()
          return true
        end

        assert.is_true(NetworkMgr:_returnOnlineState())

        NetworkMgr._isWifiConnected = orig_isWifiConnected
        NetworkMgr._hasDefaultRoute = orig_hasDefaultRoute
        NetworkMgr._canResolveHostnames = orig_canResolve
        Device.hasWifiToggle = orig_hasWifiToggle
      end
    )

    it(
      "should return false in _returnOnlineState when hasWifiToggle is true, wifi is connected, but route/DNS fails",
      function()
        local orig_hasWifiToggle = Device.hasWifiToggle
        Device.hasWifiToggle = function()
          return true
        end

        local orig_isWifiConnected = NetworkMgr._isWifiConnected
        local orig_hasDefaultRoute = NetworkMgr._hasDefaultRoute
        local orig_canResolve = NetworkMgr._canResolveHostnames

        NetworkMgr._isWifiConnected = function()
          return true
        end
        NetworkMgr._hasDefaultRoute = function()
          return false
        end
        NetworkMgr._canResolveHostnames = function()
          return false
        end

        assert.is_false(NetworkMgr:_returnOnlineState())

        NetworkMgr._isWifiConnected = orig_isWifiConnected
        NetworkMgr._hasDefaultRoute = orig_hasDefaultRoute
        NetworkMgr._canResolveHostnames = orig_canResolve
        Device.hasWifiToggle = orig_hasWifiToggle
      end
    )

    it(
      "should process subprocess _returnOnlineState result end-to-end via CommandRunner",
      function()
        local orig_wait = Device.input.waitEvent
        Device.input.waitEvent = function() end

        local orig_runForever = UIManager._run_forever
        UIManager:setRunForeverMode()

        local MockTime = require("mock_time")
        MockTime:install()

        local BackgroundRunnerWidget = requireBackgroundRunner()
        BackgroundRunnerWidget:init()
        BackgroundRunnerWidget:allowBlockingJobs(true)

        local PluginShare = require("pluginshare")
        PluginShare.stopBackgroundRunner = false
        NetworkMgr.last_online_check_time = 0
        NetworkMgr.was_online = nil

        -- Use REAL NetworkMgr:_returnOnlineState with mock network layer
        local mock_route = true
        local mock_resolve = true
        local orig_hasDefaultRoute = NetworkMgr._hasDefaultRoute
        local orig_canResolve = NetworkMgr._canResolveHostnames
        local orig_isWifiOn = NetworkMgr.isWifiOn
        local orig_isConnected = NetworkMgr.isConnected
        NetworkMgr.isWifiOn = function()
          return true
        end
        NetworkMgr.isConnected = function()
          return true
        end
        NetworkMgr._hasDefaultRoute = function()
          return mock_route
        end
        NetworkMgr._canResolveHostnames = function()
          return mock_resolve
        end

        local callback_count = 0
        require("background_jobs").insert({
          when = 1,
          repeated = 2,
          executable = "fork",
          action = function()
            return NetworkMgr:_returnOnlineState()
          end,
          callback = function(job)
            NetworkMgr:_setOnlineState(job.result == true, job.start_time)
            callback_count = callback_count + 1
          end,
        })
        notifyBackgroundJobsUpdated()

        local ffi = require("ffi")
        while callback_count < 1 do
          ffi.C.poll(nil, 0, 50)
          MockTime:increase(2)
          UIManager:handleInput()
        end

        assert.is_true(NetworkMgr.was_online)

        mock_route = false
        mock_resolve = false
        NetworkMgr.last_online_check_time = 0

        while callback_count < 2 do
          ffi.C.poll(nil, 0, 50)
          MockTime:increase(2)
          UIManager:handleInput()
        end

        assert.is_false(NetworkMgr.was_online)

        NetworkMgr._hasDefaultRoute = orig_hasDefaultRoute
        NetworkMgr._canResolveHostnames = orig_canResolve
        NetworkMgr.isWifiOn = orig_isWifiOn
        NetworkMgr.isConnected = orig_isConnected
        MockTime:uninstall()
        UIManager._run_forever = orig_runForever
        stopBackgroundRunner()
        Device.input.waitEvent = orig_wait
      end
    )

    it(
      "should raise NetworkOnline or NetworkOffline from queryOnlineState on the next tick and only when the online state flips",
      function()
        local orig_returnOnlineState = NetworkMgr._returnOnlineState
        local orig_broadcastEvent = UIManager.broadcastEvent
        local orig_nextTick = UIManager.nextTick
        local orig_was_online = NetworkMgr.was_online
        local orig_last_check = NetworkMgr.last_online_check_time
        finally(function()
          NetworkMgr._returnOnlineState = orig_returnOnlineState
          UIManager.broadcastEvent = orig_broadcastEvent
          UIManager.nextTick = orig_nextTick
          NetworkMgr.was_online = orig_was_online
          NetworkMgr.last_online_check_time = orig_last_check
        end)
        local states = { true, false, false, true, true }
        local calls = 0
        NetworkMgr._returnOnlineState = function()
          calls = calls + 1
          return states[calls]
        end
        local events = {}
        UIManager.broadcastEvent = function(_, event)
          table.insert(events, event.handler)
        end
        local ticks = {}
        UIManager.nextTick = function(_, action)
          table.insert(ticks, action)
        end
        NetworkMgr.was_online = true
        NetworkMgr.last_online_check_time = 0

        for _ = 1, #states do
          NetworkMgr:queryOnlineState()
        end

        assert.are.equal(#states, calls)
        assert.are.same({}, events)
        for _, action in ipairs(ticks) do
          action()
        end
        assert.are.same({
          "onNetworkOffline",
          "onNetworkStateChanged",
          "onNetworkOnline",
          "onNetworkStateChanged",
        }, events)
      end
    )
  end)

  describe("background online check job scheduling in init", function()
    it("should insert background fork job for online state checking", function()
      local background_jobs = require("background_jobs")
      local orig_insert = background_jobs.insert
      local inserted_jobs = {}
      background_jobs.insert = function(job)
        table.insert(inserted_jobs, job)
      end

      package.loaded["ui/network/manager"] = nil
      local NetworkMgr = require("ui/network/manager") --luacheck: ignore
      UIManager:_checkTasks()

      assert.is_true(#inserted_jobs >= 1)
      local found_fork_job = false
      for _, job in ipairs(inserted_jobs) do
        if job.executable == "fork" and type(job.action) == "function" then
          found_fork_job = true
        end
      end
      assert.is_true(found_fork_job)

      background_jobs.insert = orig_insert
    end)
  end)

  describe("Menu tables, Proxy and Power settings", function()
    local NetworkMgr
    setup(function()
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
    end)

    it("configures HTTP proxy and updates menu table", function()
      NetworkMgr:setHTTPProxy("http://proxy.example.com:8080")
      assert.is_equal(
        "http://proxy.example.com:8080",
        G_reader_settings:read("http_proxy")
      )
      assert.is_true(G_reader_settings:isTrue("http_proxy_enabled"))

      local proxy_menu = NetworkMgr:getProxyMenuTable()
      assert.is_true(proxy_menu.checked_func())
      assert.is_truthy(
        proxy_menu.text_func():find("http://proxy.example.com:8080", 1, true)
      )

      -- Disable proxy
      proxy_menu.callback()
      assert.is_false(G_reader_settings:isTrue("http_proxy_enabled"))

      -- Reset proxy via nil
      NetworkMgr:setHTTPProxy(nil)
      assert.is_false(G_reader_settings:isTrue("http_proxy_enabled"))
    end)

    it("generates power save, restore, and wifi toggle menu tables", function()
      local powersave = NetworkMgr:getPowersaveMenuTable()
      assert.is_not_nil(powersave)
      local initial_val = powersave.checked_func()
      powersave.callback()
      assert.is_not_equal(initial_val, powersave.checked_func())

      local restore = NetworkMgr:getRestoreMenuTable()
      assert.is_not_nil(restore)
      assert.is_true(restore.enabled_func())
      local initial_restore = restore.checked_func()
      restore.callback()
      assert.is_not_equal(initial_restore, restore.checked_func())

      local toggle = NetworkMgr:getWifiToggleMenuTable()
      assert.is_not_nil(toggle)
      assert.is_true(toggle.enabled_func())
    end)

    it("generates beforeWifiAction and info menu tables", function()
      local before_action = NetworkMgr:getBeforeWifiActionMenuTable()
      assert.is_not_nil(before_action)
      assert.is_truthy(before_action.text_func())

      local orig_isWifiOn = NetworkMgr.isWifiOn
      local orig_isConnected = NetworkMgr.isConnected
      NetworkMgr.isWifiOn = function()
        return false
      end
      NetworkMgr.isConnected = function()
        return false
      end

      local info_menu = NetworkMgr:getInfoMenuTable()
      assert.is_not_nil(info_menu)
      assert.is_false(info_menu.enabled_func())

      NetworkMgr.isWifiOn = function()
        return true
      end
      assert.is_true(info_menu.enabled_func())

      NetworkMgr.isWifiOn = orig_isWifiOn
      NetworkMgr.isConnected = orig_isConnected
    end)

    it("wraps callbacks and triggers connection events", function()
      local ran = false
      local wrapped = NetworkMgr:wrapCallback(function()
        ran = true
      end)
      stub(NetworkMgr, "queryOnlineState")
      wrapped()
      assert.is_true(ran)
      NetworkMgr.queryOnlineState:revert()
    end)
  end)

  describe("connection actions, toggles, and saved networks", function()
    local NetworkMgr
    local Checker

    setup(function()
      package.loaded["ui/network/manager"] = nil
      NetworkMgr = require("ui/network/manager")
      Checker = NetworkMgr.ConnectivityChecker
    end)

    describe(
      "willRerunWhenOnline, willRerunWhenConnected, runWhenOnline, and runWhenConnected",
      function()
        it("raises an error when callback is nil", function()
          assert.has_error(function()
            NetworkMgr:willRerunWhenOnline(nil)
          end)
          assert.has_error(function()
            NetworkMgr:willRerunWhenConnected(nil)
          end)
        end)

        it(
          "handles willRerunWhenOnline and runWhenOnline when online",
          function()
            local orig_isOnline = NetworkMgr.isOnline
            local orig_before = NetworkMgr._beforeWifiAction
            finally(function()
              NetworkMgr.isOnline = orig_isOnline
              NetworkMgr._beforeWifiAction = orig_before
            end)

            NetworkMgr.isOnline = function()
              return true
            end
            local before_called = false
            NetworkMgr._beforeWifiAction = function()
              before_called = true
            end

            local cb_ran = false
            local res = NetworkMgr:willRerunWhenOnline(function()
              cb_ran = true
            end)
            assert.is_false(res)
            assert.is_true(cb_ran)

            local res_run = NetworkMgr:runWhenOnline(function() end)
            assert.is_true(res_run)
            assert.is_false(before_called)
          end
        )

        it(
          "handles willRerunWhenOnline and runWhenOnline when offline",
          function()
            local orig_isOnline = NetworkMgr.isOnline
            local orig_before = NetworkMgr._beforeWifiAction
            local orig_broadcast = UIManager.broadcastEvent
            finally(function()
              NetworkMgr.isOnline = orig_isOnline
              NetworkMgr._beforeWifiAction = orig_before
              UIManager.broadcastEvent = orig_broadcast
            end)

            NetworkMgr.isOnline = function()
              return false
            end
            local before_called = false
            NetworkMgr._beforeWifiAction = function()
              before_called = true
            end
            local broadcast_event = nil
            UIManager.broadcastEvent = function(_, ev)
              broadcast_event = ev
            end

            local cb = function() end
            local res = NetworkMgr:willRerunWhenOnline(cb)
            assert.is_true(res)
            assert.is_not_nil(broadcast_event)
            assert.are.equal("onPendingOnline", broadcast_event.handler)
            assert.are.equal(cb, broadcast_event.args[1])

            local res_run = NetworkMgr:runWhenOnline(cb)
            assert.is_false(res_run)
            assert.is_true(before_called)
          end
        )

        it(
          "handles willRerunWhenConnected and runWhenConnected when connected",
          function()
            local orig_isWifiConnected = NetworkMgr._isWifiConnected
            local orig_before = NetworkMgr._beforeWifiAction
            finally(function()
              NetworkMgr._isWifiConnected = orig_isWifiConnected
              NetworkMgr._beforeWifiAction = orig_before
            end)

            NetworkMgr._isWifiConnected = function()
              return true
            end
            local before_called = false
            NetworkMgr._beforeWifiAction = function()
              before_called = true
            end

            local cb_ran = false
            local res = NetworkMgr:willRerunWhenConnected(function()
              cb_ran = true
            end)
            assert.is_false(res)
            assert.is_true(cb_ran)

            local res_run = NetworkMgr:runWhenConnected(function() end)
            assert.is_true(res_run)
            assert.is_false(before_called)
          end
        )

        it(
          "handles willRerunWhenConnected and runWhenConnected when disconnected",
          function()
            local orig_isWifiConnected = NetworkMgr._isWifiConnected
            local orig_before = NetworkMgr._beforeWifiAction
            local orig_broadcast = UIManager.broadcastEvent
            finally(function()
              NetworkMgr._isWifiConnected = orig_isWifiConnected
              NetworkMgr._beforeWifiAction = orig_before
              UIManager.broadcastEvent = orig_broadcast
            end)

            NetworkMgr._isWifiConnected = function()
              return false
            end
            local before_called = false
            NetworkMgr._beforeWifiAction = function()
              before_called = true
            end
            local broadcast_event = nil
            UIManager.broadcastEvent = function(_, ev)
              broadcast_event = ev
            end

            local cb = function() end
            local res = NetworkMgr:willRerunWhenConnected(cb)
            assert.is_true(res)
            assert.is_not_nil(broadcast_event)
            assert.are.equal("onPendingConnected", broadcast_event.handler)
            assert.are.equal(cb, broadcast_event.args[1])

            local res_run = NetworkMgr:runWhenConnected(cb)
            assert.is_false(res_run)
            assert.is_true(before_called)
          end
        )
      end
    )

    describe("_beforeWifiAction branches", function()
      local orig_isWifiConnected
      local orig_isOnline
      local orig_toggleWifiOn
      local orig_showNetworkMenu
      local orig_show
      local orig_isAndroid
      local orig_action_setting

      before_each(function()
        orig_isWifiConnected = NetworkMgr._isWifiConnected
        orig_isOnline = NetworkMgr.isOnline
        orig_toggleWifiOn = NetworkMgr.toggleWifiOn
        orig_showNetworkMenu = NetworkMgr.showNetworkMenu
        orig_show = UIManager.show
        orig_isAndroid = Device.isAndroid
        orig_action_setting = G_reader_settings:read("wifi_enable_action")
      end)

      after_each(function()
        NetworkMgr._isWifiConnected = orig_isWifiConnected
        NetworkMgr.isOnline = orig_isOnline
        NetworkMgr.toggleWifiOn = orig_toggleWifiOn
        NetworkMgr.showNetworkMenu = orig_showNetworkMenu
        UIManager.show = orig_show
        Device.isAndroid = orig_isAndroid
        G_reader_settings:save("wifi_enable_action", orig_action_setting)
        Checker:stop()
      end)

      it(
        "shows ConfirmBox to select another network when wifi is connected but offline",
        function()
          NetworkMgr._isWifiConnected = function()
            return true
          end
          local shown_box = nil
          UIManager.show = function(_, widget)
            shown_box = widget
          end
          local menu_called = false
          NetworkMgr.showNetworkMenu = function()
            menu_called = true
          end

          NetworkMgr:_beforeWifiAction()

          assert.is_not_nil(shown_box)
          assert.is_function(shown_box.ok_callback)
          shown_box.ok_callback()
          assert.is_true(menu_called)
        end
      )

      it(
        "calls toggleWifiOn when disconnected and wifi_enable_action is turn_on",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          G_reader_settings:save("wifi_enable_action", "turn_on")
          local toggle_called = false
          NetworkMgr.toggleWifiOn = function()
            toggle_called = true
          end

          NetworkMgr:_beforeWifiAction()
          assert.is_true(toggle_called)
        end
      )

      it(
        "handles wifi_enable_action ignore on Android when online vs offline",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          G_reader_settings:save("wifi_enable_action", "ignore")
          Device.isAndroid = function()
            return true
          end

          -- Online: returns early without starting ConnectivityChecker
          NetworkMgr.isOnline = function()
            return true
          end
          NetworkMgr:_beforeWifiAction()
          assert.is_false(Checker:running())

          -- Offline: starts ConnectivityChecker
          NetworkMgr.isOnline = function()
            return false
          end
          NetworkMgr:_beforeWifiAction()
          assert.is_true(Checker:running())
          NetworkMgr:_dropPendingWifiConnection(false)
        end
      )

      it(
        "handles prompt action when ConnectivityChecker is running vs not running",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          G_reader_settings:save("wifi_enable_action", "prompt")

          local shown_box = nil
          UIManager.show = function(_, widget)
            shown_box = widget
          end
          local toggle_called = false
          NetworkMgr.toggleWifiOn = function()
            toggle_called = true
          end

          -- Not running: shows ConfirmBox
          Checker:stop()
          NetworkMgr:_beforeWifiAction()
          assert.is_not_nil(shown_box)
          shown_box.ok_callback()
          assert.is_true(toggle_called)

          -- Already running: returns early without showing ConfirmBox
          shown_box = nil
          Checker:start()
          NetworkMgr:_beforeWifiAction()
          assert.is_nil(shown_box)
        end
      )
    end)

    describe("toggleWifiOn and toggleWifiOff", function()
      local orig_isWifiConnected
      local orig_isWifiOn
      local orig_turnOnWifi
      local orig_stopAsyncWifiRestoreIfSupported
      local orig_abortWifiConnection
      local orig_dropPendingWifiConnection
      local orig_networkDisconnected
      local orig_hasWifiRestore
      local orig_show
      local orig_close

      before_each(function()
        orig_isWifiConnected = NetworkMgr._isWifiConnected
        orig_isWifiOn = NetworkMgr.isWifiOn
        orig_turnOnWifi = NetworkMgr._turnOnWifi
        orig_stopAsyncWifiRestoreIfSupported =
          NetworkMgr._stopAsyncWifiRestoreIfSupported
        orig_abortWifiConnection = NetworkMgr._abortWifiConnection
        orig_dropPendingWifiConnection = NetworkMgr._dropPendingWifiConnection
        orig_networkDisconnected = NetworkMgr._networkDisconnected
        orig_hasWifiRestore = Device.hasWifiRestore
        orig_show = UIManager.show
        orig_close = UIManager.close
      end)

      after_each(function()
        NetworkMgr._isWifiConnected = orig_isWifiConnected
        NetworkMgr.isWifiOn = orig_isWifiOn
        NetworkMgr._turnOnWifi = orig_turnOnWifi
        NetworkMgr._stopAsyncWifiRestoreIfSupported =
          orig_stopAsyncWifiRestoreIfSupported
        NetworkMgr._abortWifiConnection = orig_abortWifiConnection
        NetworkMgr._dropPendingWifiConnection = orig_dropPendingWifiConnection
        NetworkMgr._networkDisconnected = orig_networkDisconnected
        Device.hasWifiRestore = orig_hasWifiRestore
        UIManager.show = orig_show
        UIManager.close = orig_close
        Checker:stop()
      end)

      it(
        "returns immediately from toggleWifiOn if already connected",
        function()
          NetworkMgr._isWifiConnected = function()
            return true
          end
          local turn_on_called = false
          NetworkMgr._turnOnWifi = function()
            turn_on_called = true
          end

          NetworkMgr:toggleWifiOn()
          assert.is_false(turn_on_called)
        end
      )

      it(
        "starts ConnectivityChecker via callback when disconnected in toggleWifiOn",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          local passed_cb = nil
          local passed_interactive = nil
          NetworkMgr._turnOnWifi = function(_, cb, interactive)
            passed_cb = cb
            passed_interactive = interactive
            return true
          end

          NetworkMgr:toggleWifiOn()
          assert.is_function(passed_cb)
          assert.is_true(passed_interactive)

          passed_cb()
          assert.is_true(Checker:running())
          assert.is_true(Checker.interactive)
        end
      )

      it(
        "handles toggleWifiOn when ConnectivityChecker is already running",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          Device.hasWifiRestore = function()
            return true
          end
          Checker:start()

          local stop_called = false
          NetworkMgr.stopAsyncWifiRestore = function()
            stop_called = true
          end
          local turn_on_args = {}
          NetworkMgr._turnOnWifi = function(_, ...)
            turn_on_args = { ... }
            return true
          end

          NetworkMgr:toggleWifiOn()
          assert.is_true(stop_called)
          assert.are.equal(0, #turn_on_args)
        end
      )

      it(
        "shows error and aborts connection when _turnOnWifi returns false",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          NetworkMgr._turnOnWifi = function()
            return false
          end
          local abort_called = false
          NetworkMgr._abortWifiConnection = function()
            abort_called = true
          end
          local shown_error = nil
          UIManager.show = function(_, widget)
            if
              widget.text and widget.text:find("Error connecting", 1, true)
            then
              shown_error = widget
            end
          end

          NetworkMgr:toggleWifiOn()
          assert.is_not_nil(shown_error)
          assert.is_true(abort_called)
        end
      )

      it(
        "shows ongoing message and does not abort when _turnOnWifi returns EBUSY",
        function()
          NetworkMgr._isWifiConnected = function()
            return false
          end
          NetworkMgr._turnOnWifi = function()
            return NetworkMgr.EBUSY
          end
          local abort_called = false
          NetworkMgr._abortWifiConnection = function()
            abort_called = true
          end
          local shown_busy = nil
          UIManager.show = function(_, widget)
            if widget.text and widget.text:find("ongoing", 1, true) then
              shown_busy = widget
            end
          end

          NetworkMgr:toggleWifiOn()
          assert.is_not_nil(shown_busy)
          assert.is_false(abort_called)
        end
      )

      it(
        "handles toggleWifiOff for off, interactive on, and non-interactive on",
        function()
          -- 1. If wifi is off: returns immediately
          NetworkMgr.isWifiOn = function()
            return false
          end
          local drop_called = false
          NetworkMgr._dropPendingWifiConnection = function()
            drop_called = true
          end
          NetworkMgr:toggleWifiOff(true)
          assert.is_false(drop_called)

          -- 2. If wifi is on and interactive == true
          NetworkMgr.isWifiOn = function()
            return true
          end
          local shown_info = nil
          local closed_info = nil
          UIManager.show = function(_, widget)
            shown_info = widget
          end
          UIManager.close = function(_, widget)
            closed_info = widget
          end
          local drop_arg = nil
          NetworkMgr._dropPendingWifiConnection = function(_, arg)
            drop_arg = arg
          end
          local disconnected_called = false
          NetworkMgr._networkDisconnected = function()
            disconnected_called = true
          end

          NetworkMgr:toggleWifiOff(true)
          assert.is_not_nil(shown_info)
          assert.are.equal(shown_info, closed_info)
          assert.is_true(drop_arg)
          assert.is_true(disconnected_called)

          -- 3. If wifi is on and interactive == false
          shown_info = nil
          closed_info = nil
          drop_arg = nil
          disconnected_called = false

          NetworkMgr:toggleWifiOff(false)
          assert.is_nil(shown_info)
          assert.is_nil(closed_info)
          assert.is_true(drop_arg)
          assert.is_true(disconnected_called)
        end
      )
    end)

    describe(
      "saved networks, asyncCheckWifiState, sysfsInterfaceOperational, and ipAddress",
      function()
        it(
          "lazily initializes nw_settings in saveNetwork, deleteNetwork, and getAllSavedNetworks",
          function()
            local settings_dir = require("datastorage"):getSettingsDir()
            local network_file = settings_dir .. "/network.lua"
            finally(function()
              os.remove(network_file)
              NetworkMgr.nw_settings = nil
            end)

            NetworkMgr.nw_settings = nil
            NetworkMgr:saveNetwork({
              ssid = "TestAP",
              password = "secret",
              psk = "psk1",
              flags = "[WPA2]",
            })
            assert.is_not_nil(NetworkMgr.nw_settings)
            local saved = NetworkMgr:getAllSavedNetworks():read("TestAP")
            assert.is_not_nil(saved)
            assert.are.equal("secret", saved.password)

            NetworkMgr.nw_settings = nil
            NetworkMgr:deleteNetwork({ ssid = "TestAP" })
            assert.is_not_nil(NetworkMgr.nw_settings)
            assert.is_nil(NetworkMgr:getAllSavedNetworks():read("TestAP"))
          end
        )

        it(
          "schedules _asyncCheckWifiState and reconnects when wifi is on but disconnected",
          function()
            local background_jobs = require("background_jobs")
            local orig_insert = background_jobs.insert
            local captured_job = nil
            background_jobs.insert = function(job)
              captured_job = job
            end
            local orig_isWifiConnected = NetworkMgr._isWifiConnected
            local orig_isWifiOn = NetworkMgr.isWifiOn
            local orig_reconnect = NetworkMgr.reconnect
            finally(function()
              background_jobs.insert = orig_insert
              NetworkMgr._isWifiConnected = orig_isWifiConnected
              NetworkMgr.isWifiOn = orig_isWifiOn
              NetworkMgr.reconnect = orig_reconnect
            end)

            NetworkMgr:_asyncCheckWifiState()
            assert.is_not_nil(captured_job)
            assert.are.equal(10, captured_job.when)
            assert.are.equal(12, captured_job.repeated)
            assert.is_function(captured_job.executable)

            local reconnected_with = nil
            NetworkMgr.reconnect = function(_, target, interactive)
              reconnected_with = { target, interactive }
            end

            NetworkMgr._isWifiConnected = function()
              return false
            end
            NetworkMgr.isWifiOn = function()
              return true
            end

            captured_job.executable()
            assert.is_not_nil(reconnected_with)
            assert.is_nil(reconnected_with[1])
            assert.is_true(reconnected_with[2])
          end
        )

        it("checks sysfsInterfaceOperational via io.open operstate", function()
          local orig_io_open = io.open
          local orig_ifname = NetworkMgr.getNetworkInterfaceName
          finally(function()
            io.open = orig_io_open
            NetworkMgr.getNetworkInterfaceName = orig_ifname
          end)

          NetworkMgr.getNetworkInterfaceName = function()
            return "wlan0"
          end

          local mock_state = "up"
          io.open = function(path, mode)
            if path:find("operstate", 1, true) then
              return {
                read = function()
                  return mock_state
                end,
                close = function() end,
              }
            end
            return orig_io_open(path, mode)
          end

          assert.is_true(NetworkMgr:sysfsInterfaceOperational())

          mock_state = "down"
          assert.is_false(NetworkMgr:sysfsInterfaceOperational())

          io.open = function()
            return nil
          end
          assert.is_false(NetworkMgr:sysfsInterfaceOperational())
        end)

        it("reads ipAddress via io.popen", function()
          local orig_io_popen = io.popen
          local orig_ifname = NetworkMgr.getNetworkInterfaceName
          finally(function()
            io.popen = orig_io_popen
            NetworkMgr.getNetworkInterfaceName = orig_ifname
          end)

          NetworkMgr.getNetworkInterfaceName = function()
            return "wlan0"
          end

          io.popen = function()
            return nil
          end
          assert.is_nil(NetworkMgr:ipAddress())

          io.popen = function()
            return {
              read = function()
                return "192.168.1.42\n"
              end,
              close = function() end,
            }
          end
          assert.are.equal("192.168.1.42\n", NetworkMgr:ipAddress())
        end)
      end
    )
  end)

  teardown(function()
    function Device:initNetworkManager() end
    function Device:hasWifiRestore()
      return false
    end
    package.loaded["ui/network/manager"] = nil
  end)
end)
