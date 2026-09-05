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

    assert
      .stub(mock_readerui.showReader)
      .was_called_with(mock_readerui, widget.dump_file)

    package.loaded["apps/reader/readerui"] = nil
    UIManager.show:revert()
    os.remove(widget.dump_file)
  end)
end)
