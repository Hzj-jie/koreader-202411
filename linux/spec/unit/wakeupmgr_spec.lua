describe("WakeupMgr", function()
    local RTC
    local WakeupMgr
    local epoch1, epoch2, epoch3

    setup(function()
        require("commonrequire")
        package.unloadAll() --luacheck: ignore
        RTC = require("ffi/rtc")
        WakeupMgr = require("device/wakeupmgr"):new{}
        -- We could theoretically test this by running the tests as root locally.
        stub(WakeupMgr, "setWakeupAlarm")
        WakeupMgr.validateWakeupAlarmByProximity = spy.new(function() return true end)

        epoch1 = RTC:secondsFromNowToEpoch(1234)
        epoch2 = RTC:secondsFromNowToEpoch(123)
        epoch3 = RTC:secondsFromNowToEpoch(9999)
    end)

    it("should add a task", function()
        WakeupMgr:addTask(1234, function() end)
        assert.is_equal(epoch1, WakeupMgr._task_queue[1].epoch)
        assert.stub(WakeupMgr.setWakeupAlarm).was.called(1)
    end)
    it("should add a task in order", function()
        WakeupMgr:addTask(9999, function() end)
        assert.is_equal(epoch1, WakeupMgr._task_queue[1].epoch)
        assert.stub(WakeupMgr.setWakeupAlarm).was.called(1)

        WakeupMgr:addTask(123, function() end)
        assert.is_equal(epoch2, WakeupMgr._task_queue[1].epoch)
        assert.stub(WakeupMgr.setWakeupAlarm).was.called(2)
    end)
    it("should execute top task", function()
        assert.is_true(WakeupMgr:wakeupAction())
    end)
    it("should have removed executed task from stack", function()
        assert.is_equal(epoch1, WakeupMgr._task_queue[1].epoch)
        assert.is_equal(epoch3, WakeupMgr._task_queue[2].epoch)
    end)
    it("should have scheduled next task after execution", function()
        assert.stub(WakeupMgr.setWakeupAlarm).was.called(3) -- 2 from addTask (the second addTask doesn't replace the upcoming task), 1 from wakeupAction (via removeTask).
    end)
    it("should remove arbitrary task from stack", function()
        WakeupMgr:removeTask(2)
        assert.is_equal(epoch1, WakeupMgr._task_queue[1].epoch)
        assert.is_equal(nil, WakeupMgr._task_queue[2])
    end)
    it("should execute last task", function()
        assert.is_true(WakeupMgr:wakeupAction())
    end)
    it("should not have scheduled a wakeup without a task", function()
        assert.stub(WakeupMgr.setWakeupAlarm).was.called(3) -- 2 from addTask, 1 from wakeupAction, 0 from removeTask (because it wasn't the upcoming task that was removed)
    end)

    describe("dodgy_rtc support", function()
        local dodgy_mgr
        local mock_callback
        local mock_spy
        local delay = 150000

        before_each(function()
            package.loaded["device/wakeupmgr"] = nil
            dodgy_mgr = require("device/wakeupmgr"):new{
                dodgy_rtc = true,
            }
            dodgy_mgr:init()
            stub(dodgy_mgr, "setWakeupAlarm")
            dodgy_mgr.validateWakeupAlarmByProximity = spy.new(function() return true end)
            mock_spy = spy.new(function() end)
            mock_callback = function(...) return mock_spy(...) end
        end)

        after_each(function()
            dodgy_mgr = nil
        end)

        it("should chain alarms when delay is > 0xFFFF", function()
            dodgy_mgr:addTask(delay, mock_callback)

            -- 150000 / 0xFFFF is ~2.28.
            -- So we expect 3 alarms in the chain:
            -- 1. epoch_150000 with mock_callback
            -- 2. epoch_84465 with DummyTaskCallback
            -- 3. epoch_18930 with DummyTaskCallback
            assert.are.equal(3, #dodgy_mgr._task_queue)

            local epoch_18930 = RTC:secondsFromNowToEpoch(18930)
            local epoch_84465 = RTC:secondsFromNowToEpoch(84465)
            local epoch_150000 = RTC:secondsFromNowToEpoch(150000)

            -- Allow ±1s tolerance due to time ticking during test execution
            assert.is_true(math.abs(dodgy_mgr._task_queue[1].epoch - epoch_18930) <= 1)
            assert.is_true(math.abs(dodgy_mgr._task_queue[2].epoch - epoch_84465) <= 1)
            assert.is_true(math.abs(dodgy_mgr._task_queue[3].epoch - epoch_150000) <= 1)

            assert.are.equal(dodgy_mgr.DummyTaskCallback, dodgy_mgr._task_queue[1].callback)
            assert.are.equal(dodgy_mgr.DummyTaskCallback, dodgy_mgr._task_queue[2].callback)
            assert.are.equal(mock_callback, dodgy_mgr._task_queue[3].callback)
        end)

        it("should execute dummy alarms and progress the chain without executing real callback", function()
            dodgy_mgr:addTask(delay, mock_callback)

            -- Execute the first dummy alarm
            assert.is_true(dodgy_mgr:wakeupAction())
            assert.spy(mock_spy).was_not.called()
            assert.are.equal(2, #dodgy_mgr._task_queue)
            assert.stub(dodgy_mgr.setWakeupAlarm).was.called(2)

            -- Execute the second dummy alarm
            assert.is_true(dodgy_mgr:wakeupAction())
            assert.spy(mock_spy).was_not.called()
            assert.are.equal(1, #dodgy_mgr._task_queue)

            -- Execute the final alarm
            assert.is_true(dodgy_mgr:wakeupAction())
            assert.spy(mock_spy).was.called(1)
            assert.are.equal(0, #dodgy_mgr._task_queue)
        end)

        it("should remove the entire chain of dummy alarms when final task is removed by callback", function()
            dodgy_mgr:addTask(delay, mock_callback)
            assert.are.equal(3, #dodgy_mgr._task_queue)

            -- Remove tasks by callback
            assert.is_true(dodgy_mgr:removeTasks(nil, mock_callback))
            assert.are.equal(0, #dodgy_mgr._task_queue)
        end)

        it("should remove the entire chain of dummy alarms when final task is removed by epoch", function()
            dodgy_mgr:addTask(delay, mock_callback)
            local final_epoch = dodgy_mgr._task_queue[3].epoch
            assert.are.equal(3, #dodgy_mgr._task_queue)

            -- Remove tasks by epoch
            assert.is_true(dodgy_mgr:removeTasks(final_epoch))
            assert.are.equal(0, #dodgy_mgr._task_queue)
        end)
    end)
end)
