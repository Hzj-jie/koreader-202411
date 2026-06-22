require("ffi_wrapper")

describe("NetworkMgr non-blocking test", function()
    local Device
    local UIManager
    local ffiutil
    local usleep_calls = 0

    setup(function()
        require("commonrequire")
        Device = require("device")
        UIManager = require("ui/uimanager")
        ffiutil = require("ffi/util")
        ffiutil.usleep = function()
            usleep_calls = usleep_calls + 1
        end

        -- Mock device capabilities
        Device.hasWifiManager = function() return true end
        Device.hasWifiToggle = function() return true end

        UIManager.show = function(self, widget)
            return widget
        end
        UIManager.close = function(self)
        end
    end)

    it("should NOT loop/block when disconnected and waiting for wpa_supplicant", function()
        package.loaded["ui/network/manager"] = nil
        local NetworkMgr = require("ui/network/manager")

        -- Mock NetworkMgr methods
        NetworkMgr.getNetworkList = function()
            return {
                { ssid = "fake1", signal_quality = 50, flags = "WPA" },
                { ssid = "fake2", signal_quality = 40, flags = "WPA" },
            }, nil
        end
        NetworkMgr.getCurrentNetwork = function()
            return nil
        end
        NetworkMgr.obtainIP = function() end
        NetworkMgr.getConfiguredNetworks = function()
            return { "fake1" }
        end

        usleep_calls = 0
        local result = NetworkMgr:reconnectOrShowNetworkMenu(nil, true, true)

        -- Assert it did not call usleep (no blocking loop)
        assert.are.equal(0, usleep_calls)
        -- Assert it returned nil (since not connected)
        assert.is_nil(result)
    end)

    it("should return false if scanning failed and yielded no results", function()
        package.loaded["ui/network/manager"] = nil
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.getNetworkList = function()
            return nil, "scan error"
        end
        local result = NetworkMgr:reconnectOrShowNetworkMenu(nil, false, false)
        assert.is_false(result)
    end)

    it("should return true if already connected to a network", function()
        package.loaded["ui/network/manager"] = nil
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.getNetworkList = function()
            return {
                { ssid = "fake1", signal_quality = 50, connected = true },
            }, nil
        end
        local obtain_ip_called = false
        NetworkMgr.obtainIP = function()
            obtain_ip_called = true
        end
        local result = NetworkMgr:reconnectOrShowNetworkMenu(nil, false, false)
        assert.is_true(result)
        assert.is_true(obtain_ip_called)
    end)

    it("should auto connect preferred network and return true", function()
        package.loaded["ui/network/manager"] = nil
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.getNetworkList = function()
            return {
                { ssid = "fake1", signal_quality = 50, password = "123" },
            }, nil
        end
        local authenticate_called = false
        NetworkMgr.authenticateNetwork = function(self_mgr, network)
            authenticate_called = true
            assert.are.equal("fake1", network.ssid)
            return true
        end
        local obtain_ip_called = false
        NetworkMgr.obtainIP = function()
            obtain_ip_called = true
        end
        local result = NetworkMgr:reconnectOrShowNetworkMenu(nil, false, false)
        assert.is_true(result)
        assert.is_true(authenticate_called)
        assert.is_true(obtain_ip_called)
    end)

    it("should show settings menu and return nil if no connected or preferred network", function()
        package.loaded["ui/network/manager"] = nil
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.getNetworkList = function()
            return {
                { ssid = "fake1", signal_quality = 50, flags = "WPA" },
            }, nil
        end
        local show_menu_called = false
        UIManager.show = function(self_ui, widget)
            show_menu_called = true
            return widget
        end
        local result = NetworkMgr:reconnectOrShowNetworkMenu(nil, true, false)
        assert.is_nil(result)
        assert.is_true(show_menu_called)
    end)
end)
