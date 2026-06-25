describe("Clock plugin tests", function()
    local Device, UIManager, PluginShare, Clock, Dispatcher
    local mock_clockwidget
    local G_reader_settings_read_stubbed = false

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
        Device = require("device")
        UIManager = require("ui/uimanager")
        PluginShare = require("pluginshare")
        Dispatcher = require("dispatcher")

        stub(Device, "hasKeys")
        stub(Device, "isTouchDevice")
        stub(UIManager, "show")
        stub(UIManager, "close")
        stub(UIManager, "scheduleIn")
        stub(UIManager, "setDirty")
        stub(Dispatcher, "registerAction")

        -- Mock clockwidget to avoid image loading/rendering
        mock_clockwidget = {
            new = spy.new(function(self, args)
                return {
                    dimen = { w = 100, h = 100 }
                }
            end)
        }
        package.loaded["plugins/clock.koplugin/clockwidget"] = mock_clockwidget
    end)

    after_each(function()
        Device.hasKeys:revert()
        Device.isTouchDevice:revert()
        UIManager.show:revert()
        UIManager.close:revert()
        UIManager.scheduleIn:revert()
        UIManager.setDirty:revert()
        Dispatcher.registerAction:revert()

        if G_reader_settings_read_stubbed then
            G_reader_settings.read:revert()
            G_reader_settings_read_stubbed = false
        end

        package.loaded["plugins/clock.koplugin/clockwidget"] = nil
        package.unload("plugins/clock.koplugin/main")
        PluginShare.pause_auto_suspend = nil
    end)

    it("initializes with keys and touch gestures, and registers to main menu", function()
        Device.hasKeys.returns(true)
        Device.isTouchDevice.returns(true)

        Clock = dofile("plugins/clock.koplugin/main.lua")

        local mock_ui = {
            menu = {
                registerToMainMenu = spy.new(function() end)
            }
        }
        Clock.ui = mock_ui
        Clock:init()

        -- Verify clockwidget instantiation
        assert.spy(mock_clockwidget.new).was_called()
        assert.is_table(Clock[1])
        assert.are.equal(100, Clock[1].dimen.w)

        -- Verify main menu registration
        assert.spy(mock_ui.menu.registerToMainMenu).was_called_with(mock_ui.menu, Clock)

        -- Verify key events and gestures
        assert.is_table(Clock.key_events)
        assert.is_table(Clock.ges_events.TapClose)

        -- Verify menu item
        local menu_items = {}
        Clock:addToMainMenu(menu_items)
        local menuItem = menu_items.clock
        assert.is_table(menuItem)
        assert.are.equal("Clock", menuItem.text)

        -- Triggering menu callback should show clock
        stub(Clock, "onClockShow")
        menuItem.callback()
        assert.stub(Clock.onClockShow).was_called()
        Clock.onClockShow:revert()
    end)

    it("handles show and scheduling timeout if configured", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        Clock.timeout = 10 -- 10 seconds timeout
        Clock:onShow()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.stub(UIManager.scheduleIn).was_called_with(match.ref(UIManager), 10, match.is_function())

        -- Verify callback closes the clock
        local call = UIManager.scheduleIn.calls[1]
        local callback = call.refs[3]
        callback()
        assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(Clock))
    end)

    it("handles show without scheduling timeout if not configured", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        Clock.timeout = nil
        Clock:onShow()

        assert.is_true(PluginShare.pause_auto_suspend)
        assert.stub(UIManager.scheduleIn).was_not_called()
    end)

    it("handles suspend and resume based on G_reader_settings", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        -- Mock G_reader_settings
        stub(G_reader_settings, "read")
        G_reader_settings_read_stubbed = true
        G_reader_settings.read.returns(true) -- clock_on_suspend = true

        -- Suspend
        Clock:onSuspend()
        assert.stub(UIManager.show).was_called_with(match.ref(UIManager), match.ref(Clock))
        assert.is_true(Clock._was_suspending)

        -- Resume
        stub(Clock, "onShow")
        Clock:onResume()
        assert.stub(Clock.onShow).was_called()
        assert.is_false(Clock._was_suspending)
    end)

    it("handles tap to close and key press close", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        Clock._visible = true
        PluginShare.pause_auto_suspend = true

        -- Tap close
        local closed = Clock:onTapClose()
        assert.is_true(closed)
        assert.is_false(Clock._visible)
        assert.is_false(PluginShare.pause_auto_suspend)
        assert.stub(UIManager.close).was_called_with(match.ref(UIManager), match.ref(Clock))
    end)

    it("handles close and sets UI dirty", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        Clock:onClose()

        assert.stub(UIManager.setDirty).was_called_with(match.ref(UIManager), nil, match.is_function())
        
        -- Extract the callback passed to setDirty
        local call = UIManager.setDirty.calls[1]
        local callback = call.refs[3]
        
        local region, dimen = callback()
        assert.are.equal("ui", region)
        assert.are.equal(Clock[1].dimen, dimen)
    end)

    it("handles key press close by delegating to onTapClose", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        stub(Clock, "onTapClose")
        Clock.onTapClose.returns(true)

        local result = Clock:onAnyKeyPressed()
        assert.is_true(result)
        assert.stub(Clock.onTapClose).was_called_with(match.ref(Clock))
        Clock.onTapClose:revert()
    end)

    it("registers action with Dispatcher on init/register", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        assert.stub(Dispatcher.registerAction).was_called_with(
            match.ref(Dispatcher),
            "clock_show",
            match.is_table()
        )
        
        -- Verify registration details
        local call = Dispatcher.registerAction.calls[1]
        local details = call.refs[3]
        assert.are.equal("none", details.category)
        assert.are.equal("ClockShow", details.event)
        assert.is_true(details.device)
    end)

    it("handles clock show and sets visibility", function()
        Device.hasKeys.returns(false)
        Device.isTouchDevice.returns(false)
        Clock = dofile("plugins/clock.koplugin/main.lua")
        Clock.ui = { menu = { registerToMainMenu = function() end } }
        Clock:init()

        Clock._visible = false

        local result = Clock:onClockShow()
        assert.is_true(result)
        assert.is_true(Clock._visible)
        assert.stub(UIManager.show).was_called_with(match.ref(UIManager), match.ref(Clock))
    end)
end)
