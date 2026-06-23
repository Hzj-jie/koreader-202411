describe("NetworkSetting module", function()
    local NetworkSetting, NetworkMgr, UIManager
    setup(function()
        require("commonrequire")
        UIManager = require("ui/uimanager")
        NetworkSetting = require("ui/widget/networksetting")
        NetworkMgr = require("ui/network/manager")
    end)

    it("should initialize properly with empty network list", function()
        local ns = NetworkSetting:new{network_list = {}}
        assert.is.falsy(ns.connected_item)
    end)

    it("should NOT call connect_callback after disconnect", function()
        stub(NetworkMgr, "disconnectNetwork")
        stub(NetworkMgr, "releaseIP")

        UIManager:quit()
        local called = false
        local network_list = {
            {
                ssid = "foo",
                signal_level = -58,
                flags = "[WPA2-PSK-CCMP][ESS]",
                signal_quality = 84,
                password = "123abc",
                connected = true,
            },
        }
        local ns = NetworkSetting:new{
            network_list = network_list,
            connect_callback = function() called = true end
        }
        ns.connected_item:disconnect()
        assert.falsy(called)

        NetworkMgr.disconnectNetwork:revert()
        NetworkMgr.releaseIP:revert()
    end)

    it("should call disconnect_callback after disconnect", function()
        stub(NetworkMgr, "disconnectNetwork")
        stub(NetworkMgr, "releaseIP")

        UIManager:quit()
        local called = false
        local network_list = {
            {
                ssid = "foo",
                signal_level = -58,
                flags = "[WPA2-PSK-CCMP][ESS]",
                signal_quality = 84,
                password = "123abc",
                connected = true,
            },
        }
        local ns = NetworkSetting:new{
            network_list = network_list,
            disconnect_callback = function() called = true end
        }
        ns.connected_item:disconnect()
        assert.truthy(called)

        NetworkMgr.disconnectNetwork:revert()
        NetworkMgr.releaseIP:revert()
    end)

    it("should set connected_item to nil after disconnect", function()
        stub(NetworkMgr, "disconnectNetwork")
        stub(NetworkMgr, "releaseIP")

        UIManager:quit()
        local network_list = {
            {
                ssid = "foo",
                signal_level = -58,
                flags = "[WPA2-PSK-CCMP][ESS]",
                signal_quality = 84,
                password = "123abc",
                connected = true,
            },
            {
                ssid = "bar",
                signal_level = -258,
                signal_quality = 44,
                flags = "[WEP][ESS]",
            },
        }
        local ns = NetworkSetting:new{network_list = network_list}
        assert.is.same("foo", ns.connected_item.info.ssid)
        ns.connected_item:disconnect()
        assert.is.falsy(ns.connected_item)

        NetworkMgr.disconnectNetwork:revert()
        NetworkMgr.releaseIP:revert()
    end)

    it("should show 'Obtaining IP...' message and call NetworkMgr:obtainIP on successful authentication", function()
        stub(NetworkMgr, "authenticateNetwork", function() return true end)
        stub(NetworkMgr, "obtainIP")
        spy.on(UIManager, "show")
        spy.on(UIManager, "close")

        local network_list = {
            {
                ssid = "foo",
                signal_level = -58,
                flags = "[WPA2-PSK-CCMP][ESS]",
                signal_quality = 84,
                password = "123abc",
                connected = false,
            },
        }
        local ns = NetworkSetting:new{network_list = network_list}
        local item = ns[1][1][1][2].items[1]

        item:connect()

        assert.spy(UIManager.show).was.called(2)
        local arg1 = UIManager.show.calls[1].refs[2]
        assert.is_not_nil(arg1)
        assert.equal("Obtaining IP address…", arg1.text)

        local arg2 = UIManager.show.calls[2].refs[2]
        assert.is_not_nil(arg2)
        assert.equal("Connected.", arg2.text)

        assert.spy(NetworkMgr.obtainIP).was.called(1)
        assert.spy(UIManager.close).was.called(1)

        NetworkMgr.authenticateNetwork:revert()
        NetworkMgr.obtainIP:revert()
        UIManager.show:revert()
        UIManager.close:revert()
    end)
end)
