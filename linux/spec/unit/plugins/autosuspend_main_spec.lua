describe("AutoSuspend main plugin module", function()
  local AutoSuspend, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    local old_canSuspend = Device.canSuspend
    Device.canSuspend = function()
      return true
    end

    AutoSuspend = require("plugins/autosuspend.koplugin/main")
    Device.canSuspend = old_canSuspend
  end)

  it("should initialize AutoSuspend plugin and check enabled flags", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    assert.is_table(inst)
    assert.is_boolean(inst:_enabled())
    assert.is_boolean(inst:_enabledStandby())
    assert.is_boolean(inst:_enabledShutdown())
  end)

  it("should add AutoSuspend configuration items to main menu and trigger callbacks", function()
    local UIManager = require("ui/uimanager")
    local orig_show = UIManager.show
    local shown_widgets = {}
    UIManager.show = function(self_uim, widget)
      table.insert(shown_widgets, widget)
    end

    local orig_canPowerOff = Device.canPowerOff
    local orig_canStandby = Device.canStandby
    Device.canPowerOff = function() return true end
    Device.canStandby = function() return true end

    local mock_menu = { updateItems = function() end }
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    local menu_items = {}
    inst:addToMainMenu(menu_items)

    -- 1. autosuspend menu item
    assert.is_table(menu_items.autosuspend)
    assert.is_string(menu_items.autosuspend.text_func())
    menu_items.autosuspend.callback(mock_menu)
    local autosuspend_spinner = shown_widgets[#shown_widgets]
    assert.is_table(autosuspend_spinner)
    if autosuspend_spinner and autosuspend_spinner.callback then
      autosuspend_spinner.callback({ hour = 1, min = 30 })
      assert.are.equal(5400, inst.auto_suspend_timeout_seconds)
    end
    if autosuspend_spinner and autosuspend_spinner.default_callback then
      autosuspend_spinner.default_callback()
    end
    if autosuspend_spinner and autosuspend_spinner.extra_callback then
      autosuspend_spinner.extra_callback({ onExit = function() end })
      assert.are.equal(-1, inst.auto_suspend_timeout_seconds)
    end

    -- 2. autoshutdown menu item
    assert.is_table(menu_items.autoshutdown)
    assert.is_string(menu_items.autoshutdown.text_func())
    menu_items.autoshutdown.callback(mock_menu)
    local autoshutdown_spinner = shown_widgets[#shown_widgets]
    assert.is_table(autoshutdown_spinner)
    if autoshutdown_spinner and autoshutdown_spinner.callback then
      autoshutdown_spinner.callback({ day = 2, hour = 12 })
      assert.are.equal(2 * 86400 + 12 * 3600, inst.autoshutdown_timeout_seconds)
    end
    if autoshutdown_spinner and autoshutdown_spinner.default_callback then
      autoshutdown_spinner.default_callback()
    end
    if autoshutdown_spinner and autoshutdown_spinner.extra_callback then
      autoshutdown_spinner.extra_callback({ onExit = function() end })
      assert.are.equal(-1, inst.autoshutdown_timeout_seconds)
    end

    -- 3. autostandby menu item
    assert.is_table(menu_items.autostandby)
    assert.is_string(menu_items.autostandby.text_func())
    assert.is_string(menu_items.autostandby.help_text)
    menu_items.autostandby.callback(mock_menu)
    local autostandby_spinner = shown_widgets[#shown_widgets]
    assert.is_table(autostandby_spinner)
    if autostandby_spinner and autostandby_spinner.callback then
      autostandby_spinner.callback({ min = 2, sec = 30 })
      assert.are.equal(150, inst.auto_standby_timeout_seconds)
    end
    if autostandby_spinner and autostandby_spinner.default_callback then
      autostandby_spinner.default_callback()
    end
    if autostandby_spinner and autostandby_spinner.extra_callback then
      autostandby_spinner.extra_callback({ onExit = function() end })
      assert.are.equal(-1, inst.auto_standby_timeout_seconds)
    end

    Device.canPowerOff = orig_canPowerOff
    Device.canStandby = orig_canStandby
    UIManager.show = orig_show
  end)

  it("should handle standby lifecycle, AllowStandbyHandler, and standby transitions", function()
    local UIManager = require("ui/uimanager")
    local orig_canStandby = Device.canStandby
    local orig_standby = Device.standby
    local orig_getNextTaskTime = UIManager.getNextTaskTime
    local orig_shiftScheduledTasksBy = UIManager.shiftScheduledTasksBy
    local orig_consumeInputEarlyAfterPM = UIManager.consumeInputEarlyAfterPM

    Device.canStandby = function() return true end
    Device.standby = function(self_dev, wake_in) end
    Device.last_standby_time = 5

    local shifted_by = nil
    UIManager.shiftScheduledTasksBy = function(self_uim, dt) shifted_by = dt end
    UIManager.consumeInputEarlyAfterPM = function() end

    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    inst.auto_standby_timeout_seconds = 10

    -- Test toggleStandbyHandler
    inst:toggleStandbyHandler(true)
    assert.is_function(inst.onAllowStandby)
    inst:toggleStandbyHandler(false)
    assert.is_nil(inst.onAllowStandby)
    inst:toggleStandbyHandler(true)

    -- Test AllowStandbyHandler with next_task_time >= 1
    UIManager.getNextTaskTime = function() return 10 end
    inst:AllowStandbyHandler()
    assert.are.equal(-5, shifted_by)

    -- Test AllowStandbyHandler with next_task_time < 1
    UIManager.getNextTaskTime = function() return 0.5 end
    inst:AllowStandbyHandler()

    -- Test preventStandby and allowStandby
    inst:preventStandby()
    inst:allowStandby()

    Device.canStandby = orig_canStandby
    Device.standby = orig_standby
    UIManager.getNextTaskTime = orig_getNextTaskTime
    UIManager.shiftScheduledTasksBy = orig_shiftScheduledTasksBy
    UIManager.consumeInputEarlyAfterPM = orig_consumeInputEarlyAfterPM
  end)

  it("should handle network connectivity events and power state changes", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    inst.auto_standby_timeout_seconds = 10

    -- Network events
    inst:onNetworkConnected()
    inst:onNetworkConnecting()
    inst:onNetworkDisconnected()

    -- Power & Wakeup events
    local wakeup_tasks_added = {}
    local wakeup_tasks_removed = {}
    Device.wakeup_mgr = {
      addTask = function(self_mgr, timeout, action)
        table.insert(wakeup_tasks_added, timeout)
      end,
      removeTasks = function(self_mgr, id, action)
        table.insert(wakeup_tasks_removed, true)
      end,
    }

    inst.autoshutdown_timeout_seconds = 3600
    inst:onSuspend()
    assert.is_true(#wakeup_tasks_added >= 1)

    inst:onResume()
    assert.is_true(#wakeup_tasks_removed >= 1)

    inst:onUnexpectedWakeupLimit()
    inst:onNotCharging()
    inst:onClose()

    Device.wakeup_mgr = nil
  end)

  it("should schedule suspend and shutdown tasks safely", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    inst:_schedule()
    inst:_unschedule()
  end)
end)
