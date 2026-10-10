describe("BatteryState plugin tests #nocov", function()
  local MockTime, module, time

  local stat = function() --luacheck: ignore
    return module:new():stat()
  end

  local function resetAll(widget)
    widget:reset(true, true, true)
    local State = getmetatable(widget.awake_state)
    widget.charging_state = State:new()
    widget.awake_state = State:new()
  end

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    time = require("ui/time")
    MockTime = require("mock_time")
    MockTime:install()
  end)

  teardown(function()
    MockTime:uninstall()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    local Device = require("device")
    local PowerD = Device:getPowerDevice()
    stub(PowerD, "isCharging")
    PowerD.isCharging.returns(false)
    stub(PowerD, "isCharged")
    PowerD.isCharged.returns(false)

    module = dofile("plugins/batterystat.koplugin/main.lua")
    G_defaults:save("BATTERY_STAT_DO_NOT_RESET", false)
  end)

  after_each(function()
    local Device = require("device")
    local PowerD = Device:getPowerDevice()
    PowerD.isCharging:revert()
    PowerD.isCharged:revert()
  end)

  it("should record charging time", function()
    local widget = stat()
    assert.is_false(widget.was_charging)
    assert.is_false(widget.was_suspending)
    resetAll(widget)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(1), widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)

    widget:onCharging()
    assert.are.equal(0, widget.awake.time)
    assert.is_true(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    -- Awake charging time should be reset.
    assert.are.equal(0, widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(time.s(1), widget.charging.time)

    widget:onNotCharging()
    assert.is_false(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    -- awake & discharging time should be reset.
    assert.are.equal(time.s(1), widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(time.s(1), widget.charging.time)

    widget:onCharging()
    assert.is_true(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    -- Awake charging time should be reset.
    assert.are.equal(0, widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(time.s(1), widget.charging.time)
  end)

  it("should record suspending time", function()
    local widget = stat()
    assert.is_false(widget.was_charging)
    assert.is_false(widget.was_suspending)
    resetAll(widget)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(1), widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)

    widget:onSuspend()
    assert.is_false(widget.was_charging)
    assert.is_true(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(1), widget.awake.time)
    assert.are.equal(time.s(1), widget.sleeping.time)
    assert.are.equal(time.s(2), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)

    widget:onResume()
    assert.is_false(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(2), widget.awake.time)
    assert.are.equal(time.s(1), widget.sleeping.time)
    assert.are.equal(time.s(3), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)

    widget:onSuspend()
    assert.is_false(widget.was_charging)
    assert.is_true(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(2), widget.awake.time)
    assert.are.equal(time.s(2), widget.sleeping.time)
    assert.are.equal(time.s(4), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)
  end)

  it("should not swap the state when several charging events fired", function()
    local widget = stat()
    assert.is_false(widget.was_charging)
    assert.is_false(widget.was_suspending)
    resetAll(widget)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(time.s(1), widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(0, widget.charging.time)

    widget:onCharging()
    assert.is_true(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    -- Awake charging time should be reset.
    assert.are.equal(0, widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(time.s(1), widget.charging.time)

    widget:onCharging()
    assert.is_true(widget.was_charging)
    assert.is_false(widget.was_suspending)
    MockTime:increase(1)
    widget:accumulate()
    assert.are.equal(0, widget.awake.time)
    assert.are.equal(0, widget.sleeping.time)
    assert.are.equal(time.s(1), widget.discharging.time)
    assert.are.equal(time.s(2), widget.charging.time)
  end)

  it(
    "should not swap the state when several suspending events fired",
    function()
      local widget = stat()
      assert.is_false(widget.was_charging)
      assert.is_false(widget.was_suspending)
      resetAll(widget)
      MockTime:increase(1)
      widget:accumulate()
      assert.are.equal(time.s(1), widget.awake.time)
      assert.are.equal(0, widget.sleeping.time)
      assert.are.equal(time.s(1), widget.discharging.time)
      assert.are.equal(0, widget.charging.time)

      widget:onSuspend()
      assert.is_false(widget.was_charging)
      assert.is_true(widget.was_suspending)
      MockTime:increase(1)
      widget:accumulate()
      assert.are.equal(time.s(1), widget.awake.time)
      assert.are.equal(time.s(1), widget.sleeping.time)
      assert.are.equal(time.s(2), widget.discharging.time)
      assert.are.equal(0, widget.charging.time)

      widget:onSuspend()
      assert.is_false(widget.was_charging)
      assert.is_true(widget.was_suspending)
      MockTime:increase(1)
      widget:accumulate()
      assert.are.equal(time.s(1), widget.awake.time)
      assert.are.equal(time.s(2), widget.sleeping.time)
      assert.are.equal(time.s(3), widget.discharging.time)
      assert.are.equal(0, widget.charging.time)

      widget:onSuspend()
      assert.is_false(widget.was_charging)
      assert.is_true(widget.was_suspending)
      MockTime:increase(1)
      widget:accumulate()
      assert.are.equal(time.s(1), widget.awake.time)
      assert.are.equal(time.s(3), widget.sleeping.time)
      assert.are.equal(time.s(4), widget.discharging.time)
      assert.are.equal(0, widget.charging.time)
    end
  )

  it(
    "should not include link to open log file when it does not exist",
    function()
      local widget = stat()
      local UIManager = require("ui/uimanager")
      stub(UIManager, "show")

      os.remove(widget.dump_file)

      widget:showStatistics()

      assert.stub(UIManager.show).was.called(1)
      local kv_page = widget.kv_page
      assert.is_not_nil(kv_page)
      assert.is_table(kv_page.kv_pairs)

      local log_entry = nil
      for _, pair in ipairs(kv_page.kv_pairs) do
        if
          type(pair) == "table"
          and pair[1]
          and pair[1]:find("battery.*log")
        then
          log_entry = pair
          break
        end
      end
      assert.is_nil(log_entry)

      UIManager.show:revert()
    end
  )

  it("should include link to open log file when it exists", function()
    local widget = stat()
    local UIManager = require("ui/uimanager")
    stub(UIManager, "show")
    stub(UIManager, "close")

    local file = io.open(widget.dump_file, "w")
    if file then
      file:write("dummy log\n")
      file:close()
    end

    widget:showStatistics()

    assert.stub(UIManager.show).was.called(1)
    local kv_page = widget.kv_page
    assert.is_not_nil(kv_page)
    assert.is_table(kv_page.kv_pairs)

    local log_entry = nil
    for _, pair in ipairs(kv_page.kv_pairs) do
      if type(pair) == "table" and pair[1] and pair[1]:find("battery.*log") then
        log_entry = pair
        break
      end
    end
    assert.is_not_nil(log_entry)
    assert.is_function(log_entry.callback)

    local mock_readerui = { showReader = stub() }
    package.loaded["apps/reader/readerui"] = mock_readerui

    log_entry.callback()

    assert.stub(UIManager.close).was_called_with(UIManager, kv_page)
    assert
      .stub(mock_readerui.showReader)
      .was_called_with(mock_readerui, widget.dump_file)

    package.loaded["apps/reader/readerui"] = nil
    UIManager.close:revert()
    UIManager.show:revert()
    os.remove(widget.dump_file)
  end)

  describe("Usage methods", function()
    local widget, Usage, State

    before_each(function()
      widget = stat()
      Usage = getmetatable(widget.awake)
      State = getmetatable(widget.awake_state)
    end)

    it("should initialize Usage with default values", function()
      local u = Usage:new()
      assert.are.equal(0, u.percentage)
      assert.are.equal(0, u.time)
      assert.are.equal(0, u:percentageRate())
      assert.are.equal(0, u:percentageRatePerHour())
      assert.are.equal("N/A", u:remainingTime())
      assert.are.equal("N/A", u:chargingTime())
    end)

    it("should append state delta correctly", function()
      local u = Usage:new()
      local s = State:new()
      MockTime:increase(60)
      u:append(s)
      assert.are.equal(time.s(60), u.time)
      assert.is_number(u.percentage)
    end)

    it("should compute percentage rates and estimates", function()
      local u = Usage:new({ percentage = 10, time = time.s(3600) })
      assert.are.equal(10 / 3600, u:percentageRate())
      assert.are.equal(10, u:percentageRatePerHour())
      assert.is_number(u:remainingTime())
      assert.is_number(u:chargingTime())
    end)

    it("should dump usage metrics into key-value pairs", function()
      local u = Usage:new({ percentage = 5, time = time.s(1800) })
      local kv = {}
      u:dump(kv, "Custom label:")
      assert.is_true(#kv >= 3)

      u:dumpRemaining(kv)
      assert.is_true(#kv >= 4)

      u:dumpCharging(kv)
      assert.is_true(#kv >= 5)
    end)
  end)

  describe("dumpToText and showStatistics", function()
    local widget, shown_widgets, dumped_lines
    local UIManager

    before_each(function()
      UIManager = require("ui/uimanager")
      widget = stat()
      shown_widgets = {}
      dumped_lines = {}

      widget.dumpOrLog = function(_, content)
        table.insert(dumped_lines, content)
      end
    end)

    it("should dump text when BATTERY_STAT_DO_NOT_DUMP is false", function()
      G_defaults:save("BATTERY_STAT_DO_NOT_DUMP", false)
      widget:dumpToText()
      assert.are.equal(1, #dumped_lines)
      assert.is_true(dumped_lines[1]:find("Dump at") ~= nil)
    end)

    it(
      "should suppress text dump when BATTERY_STAT_DO_NOT_DUMP is true",
      function()
        G_defaults:save("BATTERY_STAT_DO_NOT_DUMP", true)
        widget:dumpToText()
        assert.are.equal(0, #dumped_lines)
        G_defaults:save("BATTERY_STAT_DO_NOT_DUMP", false)
      end
    )

    it("should display statistics KeyValuePage on showStatistics", function()
      local orig_show = UIManager.show
      UIManager.show = function(_, w)
        table.insert(shown_widgets, w)
      end

      widget:showStatistics()
      assert.are.equal(1, #shown_widgets)
      assert.is_not_nil(widget.kv_page)
      assert.are.equal(widget.kv_page, shown_widgets[1])

      UIManager.show = orig_show
    end)
  end)

  describe("BatteryStatWidget callbacks and menu registration", function()
    it("should forward events from BatteryStatWidget to BatteryStat", function()
      local plugin_widget = module:new()
      local bs = plugin_widget:stat()
      local flushed, suspended, resumed = false, false, false
      local orig_flush = bs.onFlushSettings
      local orig_suspend = bs.onSuspend
      local orig_resume = bs.onResume

      bs.onFlushSettings = function()
        flushed = true
      end
      bs.onSuspend = function()
        suspended = true
      end
      bs.onResume = function()
        resumed = true
      end

      plugin_widget:onFlushSettings()
      assert.is_true(flushed)

      plugin_widget:onSuspend()
      assert.is_true(suspended)

      plugin_widget:onResume()
      assert.is_true(resumed)

      bs.onFlushSettings = orig_flush
      bs.onSuspend = orig_suspend
      bs.onResume = orig_resume
    end)

    it("should register battery statistics in main menu", function()
      local plugin_widget = module:new()
      local menu_items = {}
      plugin_widget:addToMainMenu(menu_items)

      assert.is_table(menu_items.battery_statistics)
      assert.is_function(menu_items.battery_statistics.callback)
    end)
  end)

  describe(
    "Accumulation vs reset ordering bugs in onCharging and onNotCharging",
    function()
      it(
        "should call accumulate before reset on onCharging transition",
        function()
          local widget = stat()
          local call_order = {}
          local orig_accumulate = widget.accumulate
          local orig_reset = widget.reset
          widget.accumulate = function(self)
            table.insert(call_order, "accumulate")
            return orig_accumulate(self)
          end
          widget.reset = function(self, ...)
            table.insert(call_order, "reset")
            return orig_reset(self, ...)
          end

          widget.was_charging = false
          widget:onCharging()

          assert.are.same({ "accumulate", "reset" }, call_order)
        end
      )

      it(
        "should call accumulate before reset on onNotCharging transition",
        function()
          local widget = stat()
          local call_order = {}
          local orig_accumulate = widget.accumulate
          local orig_reset = widget.reset
          widget.accumulate = function(self)
            table.insert(call_order, "accumulate")
            return orig_accumulate(self)
          end
          widget.reset = function(self, ...)
            table.insert(call_order, "reset")
            return orig_reset(self, ...)
          end

          widget.was_charging = true
          widget:onNotCharging()

          assert.are.same({ "accumulate", "reset" }, call_order)
        end
      )
    end
  )
end)
