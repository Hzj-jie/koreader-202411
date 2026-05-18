describe("KeepAlive plugin tests", function()
    local Device, KeepAlive, UIManager, PluginShare
    local original_event_hook

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

        stub(Device, "isCervantes")
        stub(Device, "isKobo")
        stub(Device, "isKindle")
        stub(Device, "isSDL")

        stub(UIManager, "show")
    end)

    after_each(function()
        Device.isCervantes:revert()
        Device.isKobo:revert()
        Device.isKindle:revert()
        Device.isSDL:revert()
        UIManager.show:revert()

        package.unload("plugins/keepalive.koplugin/main")
        PluginShare.keepalive = nil
        PluginShare.pause_auto_suspend = nil
    end)

    it("supports Cervantes and toggles pause_auto_suspend", function()
        Device.isCervantes.returns(true)

        local KeepAliveClass = dofile("plugins/keepalive.koplugin/main.lua")
        assert.is_nil(KeepAliveClass.disabled)

        local mock_ui = {
            menu = {
                registerToMainMenu = spy.new(function() end)
            }
        }
        local keepalive = KeepAliveClass:new{ ui = mock_ui }
        keepalive:init()

        assert.spy(mock_ui.menu.registerToMainMenu).was_called_with(mock_ui.menu, keepalive)

        local menu_items = {}
        keepalive:addToMainMenu(menu_items)
        local menuItem = menu_items.keep_alive
        assert.is_table(menuItem)

        -- Initially disabled
        assert.is_falsy(menuItem.checked_func())

        -- Trigger callback to enable
        local mock_touchmenu = {
            updateItems = spy.new(function() end)
        }
        menuItem.callback(mock_touchmenu)

        -- Should set pause_auto_suspend to true
        assert.is_true(PluginShare.pause_auto_suspend)
        -- Should show ConfirmBox
        assert.stub(UIManager.show).was_called()
        local confirm_box = UIManager.show.calls[1].refs[2]
        assert.are.equal("Close", confirm_box.cancel_text)
        assert.are.equal("Stay alive", confirm_box.ok_text)

        -- Simulate clicking "Stay alive" (ok_callback)
        confirm_box.ok_callback()
        assert.is_true(PluginShare.keepalive)
        assert.spy(mock_touchmenu.updateItems).was_called()

        -- Now trigger callback again to disable
        menuItem.callback(mock_touchmenu)
        -- Should set pause_auto_suspend to false
        assert.is_false(PluginShare.pause_auto_suspend)
        assert.is_false(PluginShare.keepalive)
    end)

    it("supports Kobo and toggles pause_auto_suspend", function()
        Device.isKobo.returns(true)

        local KeepAliveClass = dofile("plugins/keepalive.koplugin/main.lua")
        assert.is_nil(KeepAliveClass.disabled)

        local mock_ui = {
            menu = {
                registerToMainMenu = function() end
            }
        }
        local keepalive = KeepAliveClass:new{ ui = mock_ui }
        keepalive:init()

        local menu_items = {}
        keepalive:addToMainMenu(menu_items)
        local menuItem = menu_items.keep_alive

        -- Trigger callback to enable
        local mock_touchmenu = {
            updateItems = function() end
        }
        menuItem.callback(mock_touchmenu)

        -- Should set pause_auto_suspend to true
        assert.is_true(PluginShare.pause_auto_suspend)
    end)

    it("supports Kindle and calls LIPC preventScreenSaver", function()
        Device.isKindle.returns(true)

        -- Mock liblipclua
        local mock_handle = {
            set_int_property = spy.new(function() end),
            close = function() end
        }
        local mock_lipc = {
            init = function()
                return mock_handle
            end
        }
        package.loaded["liblipclua"] = mock_lipc
        package.loaded["libopenlipclua"] = mock_lipc

        -- We must unload liblipcs if it was loaded, to force it to re-evaluate haslipc
        package.unload("liblipcs")

        local KeepAliveClass = dofile("plugins/keepalive.koplugin/main.lua")
        assert.is_nil(KeepAliveClass.disabled)

        local mock_ui = {
            menu = {
                registerToMainMenu = function() end
            }
        }
        local keepalive = KeepAliveClass:new{ ui = mock_ui }
        keepalive:init()

        local menu_items = {}
        keepalive:addToMainMenu(menu_items)
        local menuItem = menu_items.keep_alive

        -- Trigger callback to enable
        local mock_touchmenu = {
            updateItems = function() end
        }
        menuItem.callback(mock_touchmenu)

        -- Should call LIPC set_int_property with 1
        assert.spy(mock_handle.set_int_property).was_called_with(
            mock_handle, "com.lab126.powerd", "preventScreenSaver", 1
        )

        -- Should show ConfirmBox
        assert.stub(UIManager.show).was_called()
        local confirm_box = UIManager.show.calls[1].refs[2]

        -- Confirm "Stay alive"
        confirm_box.ok_callback()
        assert.is_true(PluginShare.keepalive)

        -- Trigger callback again to disable
        menuItem.callback(mock_touchmenu)

        -- Should call LIPC set_int_property with 0
        assert.spy(mock_handle.set_int_property).was_called_with(
            mock_handle, "com.lab126.powerd", "preventScreenSaver", 0
        )
        assert.is_false(PluginShare.keepalive)

        -- Cleanup package.loaded
        package.loaded["liblipclua"] = nil
        package.loaded["libopenlipclua"] = nil
        package.unload("liblipcs")
    end)

    it("supports SDL and shows InfoMessage", function()
        Device.isSDL.returns(true)

        local KeepAliveClass = dofile("plugins/keepalive.koplugin/main.lua")
        assert.is_nil(KeepAliveClass.disabled)

        local mock_ui = {
            menu = {
                registerToMainMenu = function() end
            }
        }
        local keepalive = KeepAliveClass:new{ ui = mock_ui }
        keepalive:init()

        local menu_items = {}
        keepalive:addToMainMenu(menu_items)
        local menuItem = menu_items.keep_alive

        -- Trigger callback to enable
        local mock_touchmenu = {
            updateItems = function() end
        }
        menuItem.callback(mock_touchmenu)

        -- Should show InfoMessage then ConfirmBox
        assert.are.equal(2, #UIManager.show.calls)
        local info_msg = UIManager.show.calls[1].refs[2]
        assert.are.equal("This is a dummy implementation of 'enable' function.", info_msg.text)

        local confirm_box = UIManager.show.calls[2].refs[2]
        assert.are.equal("Close", confirm_box.cancel_text)

        -- Simulate clicking "Stay alive" to set PluginShare.keepalive = true
        confirm_box.ok_callback()

        -- Trigger disable
        UIManager.show:clear()
        menuItem.callback(mock_touchmenu)

        assert.are.equal(1, #UIManager.show.calls)
        local disable_msg = UIManager.show.calls[1].refs[2]
        assert.are.equal("This is a dummy implementation of 'disable' function.", disable_msg.text)
    end)

    it("is disabled on unsupported devices", function()
        Device.isCervantes.returns(false)
        Device.isKobo.returns(false)
        Device.isKindle.returns(false)
        Device.isSDL.returns(false)

        local KeepAliveClass = dofile("plugins/keepalive.koplugin/main.lua")
        assert.is_table(KeepAliveClass)
        assert.is_true(KeepAliveClass.disabled)
    end)
end)
