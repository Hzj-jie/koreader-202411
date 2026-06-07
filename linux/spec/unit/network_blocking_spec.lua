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
end)
