describe("AutoWarmth plugin tests", function()
  local Device, SunTime, MockTime, class, AutoWarmth, UIManager
  local original_os_date = os.date

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    package.path = "plugins/autowarmth.koplugin/?.lua;" .. package.path

    MockTime = require("mock_time")
    MockTime:install()

    -- Overwrite os.date to use the mocked os.time() value and always force UTC
    os.date = function(format, time_val)
      time_val = time_val or os.time()
      if format and format:sub(1, 1) ~= "!" then
        format = "!" .. format
      end
      return original_os_date(format, time_val)
    end

    SunTime = require("suntime")
    stub(SunTime, "getTimezoneOffset")
    SunTime.getTimezoneOffset.returns(0)
  end)

  teardown(function()
    SunTime.getTimezoneOffset:revert()
    MockTime:uninstall()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Device = require("device")
    stub(Device, "hasNaturalLight")
    Device.hasNaturalLight.returns(true)

    Device.powerd = {
      fl_warmth_max = 100,
      setWarmth = function() end,
      turnOnFrontlight = function() end,
      turnOffFrontlight = function() end,
      UIManagerReady = function() end,
    }
    stub(Device.powerd, "setWarmth")
    stub(Device.powerd, "turnOnFrontlight")
    stub(Device.powerd, "turnOffFrontlight")

    -- Default settings
    G_reader_settings:save("autowarmth_easy_mode", true)
    G_reader_settings:save("autowarmth_activate", 1) -- activate_sun
    G_reader_settings:save("autowarmth_location", "Equator")
    G_reader_settings:save("autowarmth_latitude", 0.0)
    G_reader_settings:save("autowarmth_longitude", 0.0)
    G_reader_settings:save("autowarmth_altitude", 0)
    G_reader_settings:save("autowarmth_timezone", 0)

    UIManager = require("ui/uimanager")
    UIManager:setRunForeverMode()
    UIManager:handleInput()
    UIManager:quit()

    -- Clear scheduled items from prior tests
    UIManager:unschedule(AutoWarmth)

    -- Load the plugin class
    class = dofile("plugins/autowarmth.koplugin/main.lua")

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    stub(mock_ui.menu, "registerToMainMenu")

    -- Set initial time to March 20, 2026 00:00:00 UTC (Spring Equinox)
    -- Unix timestamp: 1773964800
    MockTime:set(1773964800)

    local DeviceListener = require("device/devicelistener")
    stub(DeviceListener, "onSetNightMode")

    AutoWarmth = class:new({ ui = mock_ui })
    notifyBackgroundJobsUpdated()

    MockTime:increase(2)
    UIManager:handleInput()
  end)

  after_each(function()
    if AutoWarmth then
      AutoWarmth:_onSuspend()
      AutoWarmth = nil
    end
    local DeviceListener = require("device/devicelistener")
    if DeviceListener.onSetNightMode.revert then
      DeviceListener.onSetNightMode:revert()
    end
    UIManager:handleInput()
    Device.hasNaturalLight:revert()
    G_reader_settings:delete("autowarmth_easy_mode")
    G_reader_settings:delete("autowarmth_activate")
    G_reader_settings:delete("autowarmth_location")
    G_reader_settings:delete("autowarmth_latitude")
    G_reader_settings:delete("autowarmth_longitude")
    G_reader_settings:delete("autowarmth_altitude")
    G_reader_settings:delete("autowarmth_timezone")
  end)

  it("should load setting defaults correctly on initialization", function()
    assert.are.equal(true, AutoWarmth.easy_mode)
    assert.are.equal(1, AutoWarmth.activate)
    assert.are.equal("Equator", AutoWarmth.location)
    assert.are.equal(0.0, AutoWarmth.latitude)
    assert.are.equal(0.0, AutoWarmth.longitude)
  end)

  it("should set initial dawn warmth at midnight", function()
    -- At 00:00:00, AutoWarmth should have initialized and set initial warmth to 60 (civil dawn value)
    assert
      .stub(Device.powerd.setWarmth)
      .was_called_with(match.is_table(), 60, match._)
  end)

  describe("Dispatcher actions", function()
    local Notification

    before_each(function()
      Notification = require("ui/widget/notification")
      stub(Notification, "notify")
    end)

    after_each(function()
      Notification.notify:revert()
    end)

    it("should register actions with the Dispatcher", function()
      local Dispatcher = require("dispatcher")
      stub(Dispatcher, "registerAction")

      AutoWarmth:onDispatcherRegisterActions()

      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "show_ephemeris", {
          category = "none",
          event = "ShowEphemeris",
          title = "Show ephemeris",
          general = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_off", {
          category = "none",
          event = "AutoWarmthOff",
          title = "Auto warmth off",
          screen = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_activate_sun", {
          category = "none",
          event = "AutoWarmthMode",
          arg = 1,
          title = "Auto warmth use sun position",
          screen = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_activate_schedule", {
          category = "none",
          event = "AutoWarmthMode",
          arg = 2,
          title = "Auto warmth use schedule",
          screen = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_activate_closer_midnight", {
          category = "none",
          event = "AutoWarmthMode",
          arg = 4,
          title = "Auto warmth use closer midnight",
          screen = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_activate_closer_noon", {
          category = "none",
          event = "AutoWarmthMode",
          arg = 3,
          title = "Auto warmth use closer noon",
          screen = true,
        })
      assert
        .stub(Dispatcher.registerAction)
        .was_called_with(Dispatcher, "auto_warmth_cycle_trough", {
          category = "none",
          event = "AutoWarmthMode",
          title = "Auto warmth cycle through modes",
          screen = true,
        })

      Dispatcher.registerAction:revert()
    end)

    it("should toggle AutoWarmth off via onAutoWarmthOff", function()
      AutoWarmth:onAutoWarmthOff()
      assert.are.equal(0, AutoWarmth.activate)
      assert
        .stub(Notification.notify)
        .was_called_with(match.is_table(), "Auto warmth turned off")
    end)

    it("should select modes via onAutoWarmthMode with arguments", function()
      -- Mode 2: Fixed schedule
      AutoWarmth:onAutoWarmthMode(2)
      assert.are.equal(2, AutoWarmth.activate)
      assert
        .stub(Notification.notify)
        .was_called_with(match.is_table(), "Auto warmth use schedule")

      -- Mode 3: Closer Noon
      AutoWarmth:onAutoWarmthMode(3)
      assert.are.equal(3, AutoWarmth.activate)
      assert
        .stub(Notification.notify)
        .was_called_with(match.is_table(), "Auto warmth use whatever is closer to noon")

      -- Mode 4: Closer Midnight
      AutoWarmth:onAutoWarmthMode(4)
      assert.are.equal(4, AutoWarmth.activate)
      assert
        .stub(Notification.notify)
        .was_called_with(match.is_table(), "Auto warmth use whatever is closer to midnight")

      -- Mode 1: Sun position
      AutoWarmth:onAutoWarmthMode(1)
      assert.are.equal(1, AutoWarmth.activate)
      assert
        .stub(Notification.notify)
        .was_called_with(match.is_table(), "Auto warmth use sun position")
    end)

    it(
      "should cycle through modes sequentially via onAutoWarmthMode without arguments",
      function()
        -- Starts at 1 (activate_sun)
        assert.are.equal(1, AutoWarmth.activate)

        -- Cycle 1: 1 -> 0 (Off)
        AutoWarmth:onAutoWarmthMode()
        assert.are.equal(0, AutoWarmth.activate)
        assert
          .stub(Notification.notify)
          .was_called_with(match.is_table(), "Auto warmth turned off")

        -- Cycle 2: 0 -> 4 (Closer Midnight)
        AutoWarmth:onAutoWarmthMode()
        assert.are.equal(4, AutoWarmth.activate)
        assert
          .stub(Notification.notify)
          .was_called_with(match.is_table(), "Auto warmth use whatever is closer to midnight")

        -- Cycle 3: 4 -> 3 (Closer Noon)
        AutoWarmth:onAutoWarmthMode()
        assert.are.equal(3, AutoWarmth.activate)
        assert
          .stub(Notification.notify)
          .was_called_with(match.is_table(), "Auto warmth use whatever is closer to noon")

        -- Cycle 4: 3 -> 2 (Schedule)
        AutoWarmth:onAutoWarmthMode()
        assert.are.equal(2, AutoWarmth.activate)
        assert
          .stub(Notification.notify)
          .was_called_with(match.is_table(), "Auto warmth use schedule")

        -- Cycle 5: 2 -> 1 (Sun position)
        AutoWarmth:onAutoWarmthMode()
        assert.are.equal(1, AutoWarmth.activate)
        assert
          .stub(Notification.notify)
          .was_called_with(match.is_table(), "Auto warmth use sun position")
      end
    )
  end)

  describe("Solar Position Warmth Transitions", function()
    before_each(function()
      -- Reset stubs
      Device.powerd.setWarmth:clear()
    end)

    it(
      "should transition warmth dynamically after civil dawn towards sunrise",
      function()
        -- Reset stubs to clear initialization calls
        Device.powerd.setWarmth:clear()

        -- Advance to civil dawn (20612 seconds)
        MockTime:set(1773964800 + 20613)
        UIManager:handleInput()

        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 60, match._)

        Device.powerd.setWarmth:clear()

        -- Advance to mid-dawn (20981 seconds), warmth should have transitioned to 48
        MockTime:set(1773964800 + 20982)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 48, match._)

        Device.powerd.setWarmth:clear()

        -- Advance to post-sunrise (21842 seconds), warmth should be 20
        MockTime:set(1773964800 + 21842)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, match._)
      end
    )

    it(
      "should maintain daytime warmth until sunset, then transition to evening warmth",
      function()
        -- Advance to 12:00:00 (noon, warmth stays at 20)
        MockTime:set(1773964800 + 12 * 3600)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, match._)

        Device.powerd.setWarmth:clear()

        -- Advance to 66005 seconds (mid-sunset transition, warmth should be 38)
        MockTime:set(1773964800 + 66006)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 38, match._)

        Device.powerd.setWarmth:clear()

        -- Advance to civil dusk (66684 seconds, warmth should be 60)
        MockTime:set(1773964800 + 66684)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 60, match._)
      end
    )

    it(
      "should recalculate schedule on the next day after midnight update",
      function()
        -- Clear and advance past midnight to 01:00:00 next day
        -- (1773964800 + 25 hours = 1774054800)
        Device.powerd.setWarmth:clear()
        MockTime:set(1773964800 + 25 * 3600)
        UIManager:handleInput()

        -- Verify that it recalculated and scheduled the first warmth change of the new day
        assert.stub(Device.powerd.setWarmth).was_called()
      end
    )
  end)

  describe("Fixed Schedule Warmth Transitions", function()
    before_each(function()
      AutoWarmth:onAutoWarmthMode(2) -- Mode 2: Fixed schedule
      Device.powerd.setWarmth:clear()
    end)

    it("should transition warmth dynamically based on the schedule", function()
      -- Reset stubs to clear initialization/mode change calls
      Device.powerd.setWarmth:clear()

      -- Advance to 06:30:00 (23400 seconds)
      MockTime:set(1773964800 + 23400)
      UIManager:handleInput()
      assert
        .stub(Device.powerd.setWarmth)
        .was_called_with(match.is_table(), 60, match._)

      Device.powerd.setWarmth:clear()

      -- Advance to mid-dawn transition: 06:45:00 (24300 seconds), warmth should be 40
      MockTime:set(1773964800 + 24300)
      UIManager:handleInput()
      assert
        .stub(Device.powerd.setWarmth)
        .was_called_with(match.is_table(), 40, match._)

      Device.powerd.setWarmth:clear()

      -- Advance to post-sunrise: 07:00:00 (25200 seconds), warmth should be 20
      MockTime:set(1773964800 + 25200)
      UIManager:handleInput()
      assert
        .stub(Device.powerd.setWarmth)
        .was_called_with(match.is_table(), 20, match._)
    end)

    it(
      "should maintain daytime warmth until sunset schedule, then transition",
      function()
        -- Advance to 12:00:00 (43200 seconds), warmth remains 20
        MockTime:set(1773964800 + 12 * 3600)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, match._)

        Device.powerd.setWarmth:clear()

        -- Sunset starts at 21:30:00 (77400s), civil dusk is 22:00:00 (79200s)
        -- Mid-dusk transition: 21:45:00 (78300s)
        -- Warmth transition from 20 to 60 (diff +40) over 1800s.
        -- delta_t = 1800/40 = 45s.
        -- At 78300s, i = (78300 - 77400)/45 = 900/45 = 20.
        -- warmth = 20 + 20 = 40.
        MockTime:set(1773964800 + 78300)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 40, match._)

        Device.powerd.setWarmth:clear()

        -- Advance to civil dusk: 22:00:00 (79200 seconds), warmth should be 60
        MockTime:set(1773964800 + 79200)
        UIManager:handleInput()
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 60, match._)
      end
    )
  end)

  describe("Frontlight Toggling - Zero Offset", function()
    before_each(function()
      G_reader_settings:save("autowarmth_fl_off_during_day", true)
      G_reader_settings:save("autowarmth_easy_mode", true)
      AutoWarmth.fl_off_during_day = true
      AutoWarmth.easy_mode = true
      AutoWarmth:scheduleMidnightUpdate()
      Device.powerd.turnOffFrontlight:clear()
      Device.powerd.turnOnFrontlight:clear()
    end)

    after_each(function()
      G_reader_settings:delete("autowarmth_fl_off_during_day")
      AutoWarmth.fl_off_during_day = nil
      AutoWarmth:scheduleMidnightUpdate()
    end)

    it(
      "should toggle frontlight at sunrise and sunset with zero offset",
      function()
        -- At startup (midnight), frontlight was turned ON by toggleFrontlight.
        -- Let's clear turnOnFrontlight stub to inspect subsequent actions.
        Device.powerd.turnOnFrontlight:clear()

        -- Advance past Sunrise (21841.317s) to 21842s, and then to 21843s to trigger nested 0.01s task
        MockTime:set(1773964800 + 21842)
        UIManager:handleInput()
        MockTime:set(1773964800 + 21843)
        UIManager:handleInput()

        -- Frontlight should be turned OFF at sunrise
        assert.stub(Device.powerd.turnOffFrontlight).was_called()
        Device.powerd.turnOffFrontlight:clear()

        -- Advance past Sunset (65450.482s) to 65451s, and then to 65452s to trigger nested 0.01s task
        MockTime:set(1773964800 + 65451)
        UIManager:handleInput()
        MockTime:set(1773964800 + 65452)
        UIManager:handleInput()

        -- Frontlight should be turned ON at sunset
        assert.stub(Device.powerd.turnOnFrontlight).was_called()
      end
    )
  end)

  describe("Frontlight Toggling - 600s Offset", function()
    before_each(function()
      G_reader_settings:save("autowarmth_fl_off_during_day", true)
      G_reader_settings:save("autowarmth_easy_mode", false)
      G_reader_settings:save("autowarmth_fl_off_during_day_offset_s", 600)
      AutoWarmth.fl_off_during_day = true
      AutoWarmth.easy_mode = false
      AutoWarmth.fl_off_during_day_offset_s = 600
      AutoWarmth:scheduleMidnightUpdate()
      Device.powerd.turnOffFrontlight:clear()
      Device.powerd.turnOnFrontlight:clear()
    end)

    after_each(function()
      G_reader_settings:delete("autowarmth_fl_off_during_day")
      G_reader_settings:delete("autowarmth_easy_mode")
      G_reader_settings:delete("autowarmth_fl_off_during_day_offset_s")
      AutoWarmth.fl_off_during_day = nil
      AutoWarmth.easy_mode = true
      AutoWarmth.fl_off_during_day_offset_s = 0
      AutoWarmth:scheduleMidnightUpdate()
    end)

    it(
      "should toggle frontlight at sunrise and sunset with 600s offset",
      function()
        -- At startup (midnight), frontlight was turned ON by toggleFrontlight.
        -- Let's clear turnOnFrontlight stub to inspect subsequent actions.
        Device.powerd.turnOnFrontlight:clear()

        -- Sunrise = 21841.317s. Sunrise + 600s = 22441.317s.
        -- Advance past 22441.317s to 22442s, and then to 22443s to trigger nested 0.01s task
        MockTime:set(1773964800 + 22442)
        UIManager:handleInput()
        MockTime:set(1773964800 + 22443)
        UIManager:handleInput()

        -- Frontlight should be turned OFF at sunrise + 600s
        assert.stub(Device.powerd.turnOffFrontlight).was_called()
        Device.powerd.turnOffFrontlight:clear()

        -- Sunset = 65450.482s. Sunset - 600s = 64850.482s.
        -- Advance past 64850.482s to 64851s, and then to 64852s to trigger nested 0.01s task
        MockTime:set(1773964800 + 64851)
        UIManager:handleInput()
        MockTime:set(1773964800 + 64852)
        UIManager:handleInput()

        -- Frontlight should be turned ON at sunset - 600s
        assert.stub(Device.powerd.turnOnFrontlight).was_called()
      end
    )
  end)

  describe("Suspend and Resume Lifecycle", function()
    before_each(function()
      -- Ensure starting in Mode 1 (Solar Position)
      AutoWarmth:onAutoWarmthMode(1)
      Device.powerd.setWarmth:clear()
    end)

    it(
      "should not apply warmth transitions while suspended, and catch up instantly on resume",
      function()
        -- At startup/midnight, warmth was initialized to 60.
        -- Clear the stub to track subsequent warmth updates
        Device.powerd.setWarmth:clear()

        -- Suspend the plugin
        AutoWarmth:_onSuspend()

        -- Advance time past Sunrise (06:04:02) to 08:00:00 (28800 seconds)
        -- Unix timestamp: 1773964800 + 28800 = 1773993600
        MockTime:set(1773964800 + 28800)
        UIManager:handleInput()

        -- Verify that setWarmth was NOT called during suspend
        assert.stub(Device.powerd.setWarmth).was_not_called()

        -- Resume the plugin
        AutoWarmth:_onResume()
        UIManager:handleInput()

        -- Warmth should immediately catch up to daytime warmth (20)
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, true)
        Device.powerd.setWarmth:clear()

        -- Advance time by 2 seconds to drain the 1.5s backup/safety timer scheduled by scheduleNextWarmthChange
        MockTime:increase(2)
        UIManager:handleInput()

        -- The 1.5s timer should also set warmth to 20 (safely)
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, true)
      end
    )

    it(
      "should catch up correctly on resume when resumed on a different day",
      function()
        -- Clear the stub
        Device.powerd.setWarmth:clear()

        -- Suspend the plugin
        AutoWarmth:_onSuspend()

        -- Advance time to 08:00:00 on the next day (March 21, 2026)
        -- March 20, 2026 00:00:00 UTC + 24h + 8h = 1773964800 + 32 * 3600 = 1774080000
        MockTime:set(1773964800 + 32 * 3600)
        UIManager:handleInput()

        -- Verify that setWarmth was NOT called during suspend
        assert.stub(Device.powerd.setWarmth).was_not_called()

        -- Resume the plugin
        AutoWarmth:_onResume()
        UIManager:handleInput()

        -- It should recalculate the schedule for the new day, and set warmth immediately to daytime warmth (20)
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, true)
        Device.powerd.setWarmth:clear()

        -- Advance time by 2 seconds to drain the 1.5s backup timer
        MockTime:increase(2)
        UIManager:handleInput()

        -- The 1.5s timer should also set warmth to 20
        assert
          .stub(Device.powerd.setWarmth)
          .was_called_with(match.is_table(), 20, true)
      end
    )
  end)
end)
