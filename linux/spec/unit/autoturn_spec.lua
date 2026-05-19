describe("AutoTurn plugin tests", function()
    local UIManager, PluginShare, Device, time, MockTime
    local mock_menu, mock_topmost_widget
    local class, widget

    local function runBackgroundTasks(sec)
        MockTime:increase(sec)
        UIManager:handleInput()
    end

    local function getPageTurnCalls()
        local page_turns = {}
        if UIManager.broadcastEvent.calls then
            for _, call in ipairs(UIManager.broadcastEvent.calls) do
                local ev = call.vals[2]
                if ev and type(ev) == "table" and ev.handler == "onGotoViewRel" then
                    table.insert(page_turns, ev)
                end
            end
        end
        return page_turns
    end

    local function assertPageTurnCalled(distance)
        local page_turns = getPageTurnCalls()
        assert.is_true(#page_turns > 0, "Expected onGotoViewRel to be called, but it wasn't")
        if distance then
            local found = false
            for _, ev in ipairs(page_turns) do
                if ev.args and ev.args[1] == distance then
                    found = true
                    break
                end
            end
            assert.is_true(found, "Expected onGotoViewRel with distance " .. tostring(distance) .. " to be called")
        end
    end

    local function assertPageTurnNotCalled()
        local page_turns = getPageTurnCalls()
        assert.are.equal(0, #page_turns, "Expected onGotoViewRel NOT to be called, but it was")
    end

    local function saveAutoTurnSettings(settings)
        local LuaSettings = require("luasettings")
        local DataStorage = require("datastorage")
        local autoturn_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autoturn.lua")
        if settings.enable ~= nil then
            if settings.enable then
                autoturn_settings:makeTrue("enable")
            else
                autoturn_settings:makeFalse("enable")
            end
        end
        if settings.timeout ~= nil then
            autoturn_settings:save("autoturn_timeout_seconds", settings.timeout)
        end
        if settings.distance ~= nil then
            autoturn_settings:save("autoturn_distance", settings.distance)
        end
        autoturn_settings:flush()
    end

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))

        MockTime = require("mock_time")
        MockTime:install()
    end)

    teardown(function()
        MockTime:uninstall()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        UIManager = require("ui/uimanager")
        PluginShare = require("pluginshare")
        Device = require("device")
        time = require("ui/time")

        Device.input.waitEvent = function() end
        UIManager:setRunForeverMode()
        requireBackgroundRunner()

        mock_topmost_widget = { name = "ReaderUI" }

        stub(UIManager, "getTopmostVisibleWidget", function()
            return mock_topmost_widget
        end)
        spy.on(UIManager, "broadcastEvent")
        spy.on(UIManager, "updateLastUserActionTime")
        stub(UIManager, "show")

        mock_menu = {
            registerToMainMenu = spy.new(function() end),
            updateItems = spy.new(function() end)
        }

        -- Clean up local autoturn.lua settings
        local LuaSettings = require("luasettings")
        local DataStorage = require("datastorage")
        local autoturn_settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autoturn.lua")
        autoturn_settings:purge()

        -- Reset G_reader_settings keys we might fallback to
        G_reader_settings:delete("autoturn_timeout_seconds")
        G_reader_settings:delete("autoturn_distance")

        -- Clear background jobs to prevent test leakage
        PluginShare.backgroundJobs = {}

        UIManager._last_user_action_time = UIManager:getElapsedTimeSinceBoot()
    end)

    after_each(function()
        if widget then
            widget:onClose()
            runBackgroundTasks(2)
            widget = nil
        end

        UIManager.getTopmostVisibleWidget:revert()
        UIManager.broadcastEvent:revert()
        UIManager.updateLastUserActionTime:revert()
        UIManager.show:revert()

        G_reader_settings:delete("autoturn_timeout_seconds")
        G_reader_settings:delete("autoturn_distance")

        stopBackgroundRunner()
        package.unload("plugins/autoturn.koplugin/main")
        PluginShare.pause_auto_suspend = nil
        PluginShare.DeviceIdling = nil
    end)

    it("should load settings and register to menu on init", function()
        saveAutoTurnSettings({ enable = true, timeout = 45 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.are.equal(45, widget.autoturn_sec)
        assert.is_true(widget.enabled)

        assert.spy(mock_menu.registerToMainMenu).was_called_with(mock_menu, match.ref(widget))
    end)

    it("should not schedule autoturn if timeout is 0", function()
        saveAutoTurnSettings({ enable = true, timeout = 0 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_nil(PluginShare.pause_auto_suspend)

        -- Trigger ticks
        notifyBackgroundJobsUpdated()
        runBackgroundTasks(2)
        assertPageTurnNotCalled()
    end)

    it("should not schedule autoturn if disabled", function()
        saveAutoTurnSettings({ enable = false, timeout = 45 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_false(widget.enabled)
        assert.is_false(PluginShare.pause_auto_suspend or false)

        notifyBackgroundJobsUpdated()
        runBackgroundTasks(45)
        assertPageTurnNotCalled()
    end)

    it("should pause auto suspend when active, and resume on stop", function()
        saveAutoTurnSettings({ enable = true, timeout = 45 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_true(PluginShare.pause_auto_suspend)

        widget:_stop()
        assert.is_false(PluginShare.pause_auto_suspend)
    end)

    it("should trigger page turn when timeout expires", function()
        saveAutoTurnSettings({ enable = true, timeout = 10, distance = 2 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        notifyBackgroundJobsUpdated()

        -- Initial tick to setup background runner's internal timer
        runBackgroundTasks(2)
        assertPageTurnNotCalled()

        -- Wait until 10 seconds elapsed
        runBackgroundTasks(10)

        -- Verify page turned
        assertPageTurnCalled(2)

        -- Verify user action updated
        assert.stub(UIManager.updateLastUserActionTime).was_called(1)
    end)

    it("should not trigger page turn if topmost widget is not ReaderUI", function()
        saveAutoTurnSettings({ enable = true, timeout = 10 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        notifyBackgroundJobsUpdated()
        runBackgroundTasks(2)

        -- Set top widget to something else (e.g. a menu)
        mock_topmost_widget = { name = "Menu" }

        runBackgroundTasks(10)

        -- Page turn should not be called
        assertPageTurnNotCalled()
    end)

    it("should not trigger page turn if device is suspended/idling", function()
        saveAutoTurnSettings({ enable = true, timeout = 10 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        notifyBackgroundJobsUpdated()
        runBackgroundTasks(2)

        -- Set device idling
        PluginShare.DeviceIdling = true

        runBackgroundTasks(10)

        assertPageTurnNotCalled()
    end)

    it("should restart scheduling on resume", function()
        saveAutoTurnSettings({ enable = true, timeout = 10 })

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        notifyBackgroundJobsUpdated()
        runBackgroundTasks(2)

        -- Simulate suspend/resume
        widget:onSuspend()
        runBackgroundTasks(1)
        runBackgroundTasks(9)
        assertPageTurnNotCalled()

        widget:onResume()
        notifyBackgroundJobsUpdated()
        assert.is_true(PluginShare.pause_auto_suspend)

        runBackgroundTasks(10)
        assertPageTurnCalled()
    end)
end)
