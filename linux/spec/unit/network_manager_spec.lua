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

  teardown(function()
    function Device:initNetworkManager() end
    function Device:hasWifiRestore()
      return false
    end
    package.loaded["ui/network/manager"] = nil
  end)
end)
