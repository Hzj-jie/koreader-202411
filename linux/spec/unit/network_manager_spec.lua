describe("network_manager module", function()
  local Device
  local UIManager
  local gettext
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
    gettext = require("gettext")
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
    local MockTime = require("mock_time")
    local PluginShare = require("pluginshare")
    local NetworkMgr
    local Checker
    local original_isWifiConnected
    local original_networkConnected
    local original_abortWifiConnection
    local original_show
    local abort_called
    local connected_called
    local show_called
    local shown_message

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
      MockTime:install()
    end)

    before_each(function()
      abort_called = 0
      connected_called = 0
      show_called = 0
      shown_message = nil
      MockTime:set(100)

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
      MockTime:uninstall()
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
        MockTime:increase(10) -- 10 seconds elapsed

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
        MockTime:increase(61) -- 61 seconds elapsed

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
        MockTime:increase(61) -- 61 seconds elapsed

        Checker:executable()

        assert.is.same(connected_called, 0)
        assert.is.same(abort_called, 1)
        assert.is.same(show_called, 1)
        assert.is_not_nil(shown_message)
        assert.is_false(Checker:running())
      end
    )

    it("aborts via monotonic wall time after 60s", function()
      Checker:start(false)
      MockTime:increase(59)
      Checker:executable()
      assert.is.same(0, abort_called)
      assert.is_true(Checker:running())

      MockTime:increase(1)
      Checker:executable()
      assert.is.same(1, abort_called)
      assert.is_false(Checker:running())
    end)

    it(
      "invalidates previous background jobs on rapid stop and start",
      function()
        local jobs = PluginShare.backgroundJobs
        local before_count = #jobs

        Checker:start(false)
        assert.is.same(before_count + 1, #jobs)
        local first_job = jobs[#jobs]
        assert.is_true(first_job.repeated())

        -- Restarting within the same timestamp updates interactive without inserting a duplicate job.
        Checker:start(true)
        assert.is_true(Checker.interactive)
        assert.is.same(before_count + 1, #jobs)
        assert.is_true(first_job.repeated())

        Checker:stop()
        assert.is_false(first_job.repeated())
        first_job.executable()
        assert.is.same(0, abort_called)

        MockTime:increase(0.001)
        Checker:start(false)
        assert.is.same(before_count + 2, #jobs)
        local second_job = jobs[#jobs]
        assert.is_false(first_job.repeated())
        assert.is_true(second_job.repeated())

        MockTime:increase(61)
        first_job.executable()
        assert.is.same(0, abort_called)
        assert.is_true(Checker:running())
        assert.is_true(second_job.repeated())

        second_job.executable()
        assert.is.same(1, abort_called)
        assert.is_false(Checker:running())
        assert.is_false(second_job.repeated())
      end
    )

    it(
      "restarts timeout window and invalidates old job when started while running",
      function()
        local jobs = PluginShare.backgroundJobs

        Checker:start(false)
        local first_job = jobs[#jobs]
        MockTime:increase(50)
        Checker:executable()
        assert.is.same(0, abort_called)

        -- Simulated resume restarts the 60s window instead of inheriting elapsed time.
        Checker:start(true)
        local second_job = jobs[#jobs]
        assert.is_false(first_job.repeated())
        assert.is_true(second_job.repeated())
        assert.is_true(Checker.interactive)

        MockTime:increase(20) -- 70s from first start, 20s from restart
        first_job.executable()
        Checker:executable()
        assert.is.same(0, abort_called)
        assert.is_true(Checker:running())

        MockTime:increase(40) -- 60s from restart
        Checker:executable()
        assert.is.same(1, abort_called)
        assert.is.same(1, show_called)
        assert.is_false(Checker:running())
      end
    )

    it(
      "restarts timeout window as interactive when toggleWifiOn runs while running",
      function()
        local orig_turn_on = NetworkMgr._turnOnWifi
        local orig_force = UIManager.forceRepaint
        finally(function()
          NetworkMgr._turnOnWifi = orig_turn_on
          UIManager.forceRepaint = orig_force
        end)
        NetworkMgr._turnOnWifi = function()
          return true
        end
        UIManager.forceRepaint = function() end

        local jobs = PluginShare.backgroundJobs
        Checker:start(false)
        local first_job = jobs[#jobs]
        MockTime:increase(50)

        NetworkMgr:toggleWifiOn()
        local second_job = jobs[#jobs]
        assert.is_false(first_job.repeated())
        assert.is_true(second_job.repeated())
        assert.is_true(Checker.interactive)

        show_called = 0
        MockTime:increase(20) -- 70s from initial restore, 20s since manual retry
        Checker:executable()
        assert.is.same(0, abort_called)
        assert.is_true(Checker:running())

        MockTime:increase(40) -- 60s since manual retry
        Checker:executable()
        assert.is.same(1, abort_called)
        assert.is.same(1, show_called)
        assert.are.equal(
          gettext("Error connecting to the network"),
          shown_message.text
        )
        assert.is_false(Checker:running())
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

  teardown(function()
    function Device:initNetworkManager() end
    function Device:hasWifiRestore()
      return false
    end
    package.loaded["ui/network/manager"] = nil
  end)
end)
