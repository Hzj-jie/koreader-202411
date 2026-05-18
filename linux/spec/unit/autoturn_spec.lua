describe("AutoTurn plugin tests", function()
    local UIManager, PluginShare, Device, AutoTurn, time
    local mock_menu
    local mock_time_since_action, mock_topmost_widget

    setup(function()
        require("commonrequire")
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    teardown(function()
        package.unloadAll()
        require("document/canvascontext"):init(require("device"))
    end)

    before_each(function()
        UIManager = require("ui/uimanager")
        PluginShare = require("pluginshare")
        Device = require("device")
        time = require("ui/time")

        mock_time_since_action = time.s(0)
        mock_topmost_widget = { name = "ReaderUI" }

        stub(UIManager, "scheduleIn")
        stub(UIManager, "unschedule")
        stub(UIManager, "getTopmostVisibleWidget", function()
            return mock_topmost_widget
        end)
        stub(UIManager, "broadcastEvent")
        stub(UIManager, "updateLastUserActionTime")
        stub(UIManager, "show")
        stub(UIManager, "timeSinceLastUserAction", function()
            return mock_time_since_action
        end)

        mock_menu = {
            registerToMainMenu = spy.new(function() end),
            updateItems = spy.new(function() end)
        }

        -- Reset G_reader_settings keys we use
        G_reader_settings:delete("autoturn_timeout_seconds")
        G_reader_settings:delete("autoturn_distance")
        G_reader_settings:delete("autoturn_enabled")
    end)

    after_each(function()
        UIManager.scheduleIn:revert()
        UIManager.unschedule:revert()
        UIManager.getTopmostVisibleWidget:revert()
        UIManager.broadcastEvent:revert()
        UIManager.updateLastUserActionTime:revert()
        UIManager.show:revert()
        UIManager.timeSinceLastUserAction:revert()

        G_reader_settings:delete("autoturn_timeout_seconds")
        G_reader_settings:delete("autoturn_distance")
        G_reader_settings:delete("autoturn_enabled")

        package.unload("plugins/autoturn.koplugin/main")
        PluginShare.pause_auto_suspend = nil
    end)

    it("should load settings and register to menu on init", function()
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.are.equal(45, widget.autoturn_sec)
        assert.is_true(widget.enabled)

        assert.spy(mock_menu.registerToMainMenu).was_called_with(mock_menu, match.ref(widget))
    end)

    it("should not schedule autoturn if disabled or timeout is 0", function()
        -- Case A: Enabled but timeout is 0
        G_reader_settings:save("autoturn_timeout_seconds", 0)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_nil(PluginShare.pause_auto_suspend)
        assert.stub(UIManager.scheduleIn).was_not_called()

        -- Reset for Case B
        UIManager.scheduleIn:clear()
        package.unload("plugins/autoturn.koplugin/main")

        -- Case B: Disabled but timeout > 0
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeFalse("autoturn_enabled")

        class = dofile("plugins/autoturn.koplugin/main.lua")
        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_nil(PluginShare.pause_auto_suspend)
        assert.stub(UIManager.scheduleIn).was_not_called()
    end)

    it("should schedule autoturn task if enabled and timeout > 0", function()
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.is_true(widget.scheduled)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 45, match.is_function())
    end)

    it("should trigger page turn and reschedule when timeout expires", function()
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        -- Clear init schedule calls
        UIManager.scheduleIn:clear()

        -- Configure UIManager stubs for expiration
        mock_time_since_action = time.s(45)
        mock_topmost_widget = { name = "ReaderUI" }

        -- Trigger the task manually
        widget.task()

        -- Verify event broadcasted
        assert.stub(UIManager.broadcastEvent).was_called(1)
        local call = UIManager.broadcastEvent.calls[1]
        local ev = call.vals[2]
        assert.is_table(ev)
        assert.are.equal("onGotoViewRel", ev.handler)
        assert.are.equal(1, ev.args[1])

        -- Verify user action time updated
        assert.stub(UIManager.updateLastUserActionTime).was_called(1)

        -- Verify rescheduled
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 45, widget.task)
    end)

    it("should unschedule task and reset pause_auto_suspend on close/close-document/suspend", function()
        -- Case A: onClose
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.is_true(widget.scheduled)
        local task_ref = widget.task

        UIManager.unschedule:clear()
        widget:onClose()

        assert.is_false(PluginShare.pause_auto_suspend)
        assert.is_false(widget.scheduled)
        assert.is_nil(widget.task)
        assert.stub(UIManager.unschedule).was_called_with(UIManager, task_ref)

        -- Case B: onCloseDocument
        package.unload("plugins/autoturn.koplugin/main")
        PluginShare.pause_auto_suspend = nil

        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.is_true(widget.scheduled)
        task_ref = widget.task

        UIManager.unschedule:clear()
        widget:onCloseDocument()

        assert.is_false(PluginShare.pause_auto_suspend)
        assert.is_false(widget.scheduled)
        assert.stub(UIManager.unschedule).was_called_with(UIManager, task_ref)

        -- Case C: onSuspend
        package.unload("plugins/autoturn.koplugin/main")
        PluginShare.pause_auto_suspend = nil

        widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.is_true(widget.scheduled)
        task_ref = widget.task

        UIManager.unschedule:clear()
        widget:onSuspend()

        assert.is_false(PluginShare.pause_auto_suspend)
        assert.is_false(widget.scheduled)
        assert.stub(UIManager.unschedule).was_called_with(UIManager, task_ref)
    end)

    it("should restart scheduling on resume", function()
        G_reader_settings:save("autoturn_timeout_seconds", 45)
        G_reader_settings:makeTrue("autoturn_enabled")

        local class = dofile("plugins/autoturn.koplugin/main.lua")
        local widget = class:new{ ui = { menu = mock_menu } }
        widget:init()

        -- Clear stubs after init
        UIManager.scheduleIn:clear()
        PluginShare.pause_auto_suspend = nil

        widget:_onResume()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.is_true(widget.scheduled)
        assert.stub(UIManager.scheduleIn).was_called_with(UIManager, 45, widget.task)
    end)
end)



