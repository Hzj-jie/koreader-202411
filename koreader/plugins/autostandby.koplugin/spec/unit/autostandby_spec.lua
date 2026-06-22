describe("AutoStandby plugin tests", function()
    local Device, PowerD, MockTime, class, AutoStandby, UIManager, original_event_hook

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))

        MockTime = require("mock_time")
        MockTime:install()

        PowerD = require("device/generic/powerd"):new()
        stub(PowerD, "getCapacityHW")
        PowerD.getCapacityHW.returns(100) -- Default 100% battery
    end)

    teardown(function()
        PowerD.getCapacityHW:revert()
        MockTime:uninstall()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        Device = require("device")
        stub(Device, "isPocketBook")
        Device.isPocketBook.returns(true) -- Enable plugin

        Device.powerd = PowerD
        PowerD.getCapacityHW.returns(100) -- Reset to default 100% battery to ensure test isolation
        Device.input.waitEvent = function() end

        UIManager = require("ui/uimanager")
        original_event_hook = UIManager.event_hook
        UIManager.event_hook = {
            registerWidget = spy.new(function() end)
        }
        UIManager:setRunForeverMode()
        stub(UIManager, "preventStandby")
        stub(UIManager, "allowStandby")
        stub(UIManager, "scheduleIn")
        stub(UIManager, "unschedule")

        UIManager:handleInput()
        UIManager:updateLastUserActionTime()
        UIManager:quit()

        -- Ensure clean slate by removing settings file before loading plugin
        os.remove("settings/autostandby.lua")

        class = dofile("plugins/autostandby.koplugin/main.lua")
        local mock_ui = {
            menu = {
                registerToMainMenu = function() end
            }
        }
        AutoStandby = class:new{ ui = mock_ui }

        -- We need to manually trigger init because dofile returns the class,
        -- and we instantiate it, but we might need to call init if it's not automatic.
        -- In KOReader, plugins are initialized by PluginManager, which calls init().
        AutoStandby:init()

        MockTime:increase(2)
        UIManager:handleInput()
    end)

    after_each(function()
        if AutoStandby then
            AutoStandby:onClose()
        end
        MockTime:increase(2)
        UIManager:handleInput()
        AutoStandby = nil
        if class then
            class.delay = 0
            class.lastInput = 0
            class.preventing = false
        end
        Device.isPocketBook:revert()
        UIManager.preventStandby:revert()
        UIManager.allowStandby:revert()
        UIManager.scheduleIn:revert()
        UIManager.unschedule:revert()
        UIManager.event_hook = original_event_hook
    end)

    it("should initialize settings with defaults if not present", function()
        local settings = AutoStandby.settings
        assert.is_true(settings:has("filter"))
        assert.are.equal(false, settings:read("forbidden"))
        assert.are.equal(1, settings:read("filter"))
        assert.are.equal(1, settings:read("min"))
        assert.are.equal(1.5, settings:read("mul"))
        assert.are.equal(30, settings:read("max"))
        assert.are.equal(5, settings:read("win"))
        assert.are.equal(60, settings:read("bat"))
    end)

    it("should schedule standby allow after min delay on input event", function()
        AutoStandby:onInputEvent()

        assert.stub(UIManager.unschedule).was_called_with(UIManager, class.allow)
        assert.stub(UIManager.preventStandby).was_called_with(UIManager)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 1, class.allow, class)
    end)

    it("should adaptively scale delay and reset it based on input frequencies", function()
        -- 1. First input (T0) -> sets delay to min (1s)
        AutoStandby:onInputEvent()
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 1, class.allow, class)

        -- 2. Second input (T0 + 0.5s) -> too close, should be ignored
        UIManager.scheduleIn:clear()
        UIManager.unschedule:clear()
        MockTime:increase(0.5)
        AutoStandby:onInputEvent()
        assert.stub(UIManager.scheduleIn).was_not_called()
        assert.stub(UIManager.unschedule).was_not_called()

        -- 3. Third input (T0 + 1.5s) -> not filtered, scales up delay to (1+1)*1.5 = 3s
        UIManager.scheduleIn:clear()
        UIManager.unschedule:clear()
        MockTime:increase(1.0) -- total 1.5s since T0
        AutoStandby:onInputEvent()
        assert.stub(UIManager.unschedule).was_called_with(UIManager, class.allow)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 3, class.allow, class)

        -- 4. Fourth input (T0 + 3.5s) -> not filtered, scales up delay to (3+1)*1.5 = 6s
        UIManager.scheduleIn:clear()
        UIManager.unschedule:clear()
        MockTime:increase(2.0) -- total 3.5s since T0
        AutoStandby:onInputEvent()
        assert.stub(UIManager.unschedule).was_called_with(UIManager, class.allow)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 6, class.allow, class)

        -- 5. Fifth input (T0 + 34.5s) -> too far apart (> max=30s), resets delay back to min (1s)
        UIManager.scheduleIn:clear()
        UIManager.unschedule:clear()
        MockTime:increase(31.0) -- total 34.5s since T0
        AutoStandby:onInputEvent()
        assert.stub(UIManager.unschedule).was_called_with(UIManager, class.allow)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 1, class.allow, class)
    end)

    it("should trigger aggressive standby when battery drops below threshold", function()
        -- Scenario A: First input event on low battery (50%)
        PowerD.getCapacityHW.returns(50)
        AutoStandby:onInputEvent()

        -- Verify no prevention scheduled
        assert.stub(UIManager.preventStandby).was_not_called()
        assert.stub(UIManager.scheduleIn).was_not_called()

        -- Reset mock states
        UIManager.preventStandby:clear()
        UIManager.allowStandby:clear()
        UIManager.scheduleIn:clear()
        UIManager.unschedule:clear()

        -- Scenario B: First input event on high battery, followed by second input event on low battery
        PowerD.getCapacityHW.returns(100)
        AutoStandby:onInputEvent()
        assert.stub(UIManager.preventStandby).was_called_with(UIManager)
        assert.is_true(class.preventing)

        -- Now battery drops to low (50%)
        PowerD.getCapacityHW.returns(50)

        -- Trigger another input (make sure time progressed enough to not be filtered)
        MockTime:increase(2.0)
        UIManager.preventStandby:clear()
        UIManager.allowStandby:clear()
        AutoStandby:onInputEvent()
        
        -- Verify standby is allowed immediately because of low battery
        assert.stub(UIManager.allowStandby).was_called_with(UIManager)
        assert.is_false(class.preventing)
    end)

    it("should always prevent standby when forbidden by configuration", function()
        -- Set standby to forbidden in config
        AutoStandby.settings:save("forbidden", true)

        -- First input event
        AutoStandby:onInputEvent()

        -- Verify we prevented standby and did not schedule a timeout to allow it
        assert.stub(UIManager.preventStandby).was_called_with(UIManager)
        assert.stub(UIManager.scheduleIn).was_not_called()
        assert.is_true(class.preventing)

        -- Now allow it in config again
        AutoStandby.settings:save("forbidden", false)
        UIManager.preventStandby:clear()
        UIManager.scheduleIn:clear()

        -- We need to advance time so the next event is not filtered
        MockTime:increase(2)
        AutoStandby:onInputEvent()

        -- Now it should schedule allow after scaled delay (3s) as usual
        assert.stub(UIManager.preventStandby).was_not_called()
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 3, class.allow, class)
    end)
end)
