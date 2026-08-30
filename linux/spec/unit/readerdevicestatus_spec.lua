describe("ReaderDeviceStatus", function()
  local ReaderDeviceStatus
  local UIManager
  local mock_device
  local mock_powerd
  local can_restart = false

  setup(function()
    require("commonrequire")

    -- Mock Device and powerd
    mock_powerd = {
      isCharging = function()
        return false
      end,
      getCapacity = function()
        return 15
      end, -- 15% (below 20% threshold)
    }

    mock_device = {
      hasBattery = function()
        return true
      end,
      isAndroid = function()
        return false
      end,
      isKindle = function()
        return false
      end,
      hasDPad = function()
        return false
      end,
      hasKeyboard = function()
        return false
      end,
      isTouchDevice = function()
        return true
      end,
      canSuspend = function()
        return false
      end,
      canRestart = function()
        return can_restart
      end,
      getPowerDevice = function()
        return mock_powerd
      end,
      total_standby_time = 0,
      total_suspend_time = 0,
      _UIManagerReady = function() end,
      input = { group = { Any = "Any" } },
      screen = {
        getSize = function()
          return { w = 600, h = 800 }
        end,
        getWidth = function()
          return 600
        end,
        getHeight = function()
          return 800
        end,
        scaleBySize = function(self, v)
          return v
        end,
        scaleByDPI = function(self, v)
          return v
        end,
      },
    }

    package.loaded["device"] = mock_device

    -- Mock G_reader_settings
    _G.G_reader_settings = {
      read = function(self, key)
        if key == "device_status_battery_threshold" then
          return 20
        end
        if key == "device_status_battery_threshold_high" then
          return 95
        end
      end,
      isTrue = function(self, key)
        if key == "device_status_battery_alarm" then
          return true
        end
      end,
      nilOrTrue = function(self, _key)
        return true
      end,
      has = function(self, key)
        if
          key == "device_status_battery_threshold"
          or key == "device_status_battery_threshold_high"
        then
          return true
        end
        return false
      end,
    }

    local last_shown_widget
    local scheduled_funcs = {}
    local Event = require("ui/event")

    UIManager = {
      show = spy.new(function(self, widget)
        last_shown_widget = widget
        widget:handleEvent(Event:new("Show"))
      end),
      close = spy.new(function(self, widget)
        if last_shown_widget == widget then
          last_shown_widget = nil
          widget:broadcastEvent(Event:new("Close"))
        end
      end),
      closeIfShown = spy.new(function(self, widget)
        if last_shown_widget == widget then
          last_shown_widget = nil
          widget:broadcastEvent(Event:new("Close"))
        end
      end),
      scheduleIn = spy.new(function(self, delay, func)
        scheduled_funcs[delay] = func
      end),
      nextTick = spy.new(function(self, func)
        func()
      end),
      broadcastEvent = spy.new(function(self, event) end),
      unschedule = spy.new(function(self, func)
        for delay, f in pairs(scheduled_funcs) do
          if f == func then
            scheduled_funcs[delay] = nil
            break
          end
        end
      end),
      setDirty = spy.new(function() end),
      ignoreWidgetRepaint = spy.new(function() end),
      getTopmostVisibleWidget = function()
        return nil
      end,
      getLastShownWidget = function()
        return last_shown_widget
      end,
      getScheduledFuncs = function()
        return scheduled_funcs
      end,
      isWindowWidget = function()
        return true
      end,
      topdown_windows_iter = function()
        return function() return nil end
      end,
    }
    package.loaded["ui/uimanager"] = UIManager

    ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
  end)

  teardown(function()
    package.loaded["device"] = nil
    package.loaded["ui/uimanager"] = nil
    _G.G_reader_settings = nil
  end)

  it(
    "should show low battery dialog with Remind later option and timeout",
    function()
      local rds = ReaderDeviceStatus:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })

      -- Initial check should show dialog
      rds:_checkBatteryStatus()
      local dialog = UIManager.getLastShownWidget()
      assert.truthy(dialog)
      assert.are.equal("Remind later", dialog.cancel_text)
      assert.are.equal("Dismiss", dialog.ok_text)
      assert.are.equal(295, dialog.timeout)

      -- Verify timeout is scheduled
      local scheduled = UIManager.getScheduledFuncs()
      local timeout_func = scheduled[295]
      assert.truthy(timeout_func)

      -- Simulate timeout (dialog auto-closes)
      timeout_func()
      scheduled[295] = nil -- Simulate scheduler removing it after firing
      assert.is_nil(UIManager.getLastShownWidget())

      -- Check again, should show dialog again because it timed out (not dismissed)
      rds:_checkBatteryStatus()
      local dialog2 = UIManager.getLastShownWidget()
      assert.truthy(dialog2)
      assert.are.equal(295, dialog2.timeout)

      -- Verify new timeout is scheduled
      assert.truthy(scheduled[295])

      -- Simulate user tapping "Dismiss" (closes early)
      dialog2.ok_callback()
      UIManager:close(dialog2)

      -- Now it should be unscheduled
      assert.is_nil(scheduled[295])

      -- Check again, should NOT show dialog (it should return early)
      local spy_show = spy.on(UIManager, "show")
      rds:_checkBatteryStatus()
      assert.spy(spy_show).was.called(0)
      UIManager.show:revert()
    end
  )

  it("should show high memory dialog with Exit option and timeout", function()
    local original_io_open = io.open
    io.open = function(path, mode)
      if path == "/proc/self/statm" then
        return {
          read = function()
            return 100000, 51200
          end,
          close = function() end,
        }
      end
      return original_io_open(path, mode)
    end

    local rds = ReaderDeviceStatus:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })

    rds:_checkMemoryStatus()

    local dialog = UIManager.getLastShownWidget()
    assert.truthy(dialog)
    assert.are.equal("Exit", dialog.ok_text)
    assert.are.equal(295, dialog.timeout)

    -- Verify timeout is scheduled
    local scheduled = UIManager.getScheduledFuncs()
    local timeout_func = scheduled[295]
    assert.truthy(timeout_func)

    -- Simulate timeout
    timeout_func()
    scheduled[295] = nil
    assert.is_nil(UIManager.getLastShownWidget())

    io.open = original_io_open
  end)

  it(
    "should show high memory dialog with Restart option and timeout",
    function()
      can_restart = true

      local original_io_open = io.open
      io.open = function(path, mode)
        if path == "/proc/self/statm" then
          return {
            read = function()
              return 100000, 51200
            end,
            close = function() end,
          }
        end
        return original_io_open(path, mode)
      end

      local rds = ReaderDeviceStatus:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })

      rds:_checkMemoryStatus()

      local dialog = UIManager.getLastShownWidget()
      assert.truthy(dialog)
      assert.are.equal("Restart", dialog.ok_text)
      assert.are.equal(295, dialog.timeout)

      -- Simulate timeout
      local scheduled = UIManager.getScheduledFuncs()
      local timeout_func = scheduled[295]
      timeout_func()
      scheduled[295] = nil
      assert.is_nil(UIManager.getLastShownWidget())

      -- Clean up
      can_restart = false
      io.open = original_io_open
    end
  )

  it("should handle critical battery and high battery alerts", function()
    local rds = ReaderDeviceStatus:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })

    -- Critical battery (<= 5) with canSuspend
    mock_device.canSuspend = function() return true end
    mock_powerd.getCapacity = function() return 3 end
    mock_powerd.isCharging = function() return false end
    UIManager.suspend = spy.new(function() end)

    rds:_checkBatteryStatus()
    local crit_dialog = UIManager.getLastShownWidget()
    assert.truthy(crit_dialog)
    local scheduled = UIManager.getScheduledFuncs()
    assert.truthy(scheduled[3])
    scheduled[3]()
    assert.spy(UIManager.suspend).was.called(1)
    mock_device.canSuspend = function() return false end

    -- Reset dismissed state with normal battery
    mock_powerd.getCapacity = function() return 50 end
    mock_powerd.isCharging = function() return false end
    rds:_checkBatteryStatus()

    -- High battery (> threshold_high = 95) while charging
    mock_powerd.isCharging = function() return true end
    mock_powerd.getCapacity = function() return 98 end
    rds:_checkBatteryStatus()
    local high_dialog = UIManager.getLastShownWidget()
    assert.truthy(high_dialog)
    if high_dialog.ok_callback then
      high_dialog.ok_callback()
    end

    -- Reset dismissed when charge <= 95
    mock_powerd.getCapacity = function() return 90 end
    rds:_checkBatteryStatus()

    -- onTimesChange_5M
    _G.G_reader_settings.isTrue = function(self, key) return true end
    rds:onTimesChange_5M()
  end)

  it("should handle memory auto-restart and menu callbacks", function()
    local rds = ReaderDeviceStatus:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })

    can_restart = true
    local original_io_open = io.open
    io.open = function(path, mode)
      if path == "/proc/self/statm" then
        return {
          read = function() return 100000, 51200 end,
          close = function() end,
        }
      end
      return original_io_open(path, mode)
    end

    -- Test auto-restart when top widget is ReaderUI
    UIManager.getTopmostVisibleWidget = function() return { name = "ReaderUI" } end
    _G.G_reader_settings.isTrue = function(self, key) return true end
    rds:_checkMemoryStatus()
    local restart_dialog = UIManager.getLastShownWidget()
    assert.truthy(restart_dialog)
    local scheduled = UIManager.getScheduledFuncs()
    if scheduled[3] then scheduled[3]() end

    -- Test addToMainMenu items
    local menu_items = {}
    rds:addToMainMenu(menu_items)
    assert.truthy(menu_items.device_status_alarm)

    _G.G_reader_settings.flipNilOrFalse = spy.new(function() end)
    _G.G_reader_settings.save = spy.new(function() end)
    local mock_menu = { updateItems = function() end }

    for _, item in ipairs(menu_items.device_status_alarm.sub_item_table) do
      if item.text_func then item:text_func() end
      if item.enabled_func then item:enabled_func() end
      if item.checked_func then item:checked_func() end
      if item.callback then
        item.callback(mock_menu)
        local top = UIManager.getLastShownWidget()
        if top and top.callback then
          if top.left_value then
            top.callback(15, 90)
          elseif top.value then
            top.callback({ value = 150 })
          end
        end
      end
    end

    can_restart = false
    io.open = original_io_open
  end)
end)
