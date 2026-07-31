local stub = require("luassert.stub")

describe("WpaSupplicant network module", function()
  local WpaSupplicant
  local mock_wpaclient

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    mock_wpaclient = {
      new = function()
        return nil, "Client error"
      end,
    }
    package.loaded["lj-wpaclient/wpaclient"] = mock_wpaclient
    WpaSupplicant = require("ui/network/wpa_supplicant")
    WpaSupplicant.wpa_supplicant = { ctrl_interface = "/var/run/wpa_supplicant" }
  end)

  it("should expose WpaSupplicant helper module", function()
    assert.is_table(WpaSupplicant)
  end)

  it("should handle error when WpaClient fails to initialize in getNetworkList", function()
    stub(mock_wpaclient, "new", function()
      return nil, "Control socket failed"
    end)

    local list, err = WpaSupplicant:getNetworkList()
    assert.is_nil(list)
    assert.is_not_nil(err)

    mock_wpaclient.new:revert()
  end)

  it("should handle scanning results with saved networks and decoded SSIDs", function()
    local mock_nw = {
      ssid = "\\x54\\x65\\x73\\x74", -- "Test"
      bssid = "00:11:22:33:44:55",
      getSignalQuality = function() return 80 end,
    }

    local mock_cli = {
      scanThenGetResults = function()
        return { mock_nw }
      end,
      close = function() end,
    }

    stub(mock_wpaclient, "new", function() return mock_cli end)
    stub(WpaSupplicant, "getAllSavedNetworks", function()
      return {
        read = function() return { password = "pass", psk = "123456" } end,
      }
    end)
    stub(WpaSupplicant, "getCurrentNetwork", function()
      return { ssid = "Test", bssid = "00:11:22:33:44:55", id = 1 }
    end)

    local list = WpaSupplicant:getNetworkList()
    assert.is_table(list)
    assert.are.equal("Test", list[1].ssid)
    assert.is_true(list[1].connected)

    WpaSupplicant.getCurrentNetwork:revert()
    WpaSupplicant.getAllSavedNetworks:revert()
    mock_wpaclient.new:revert()
  end)

  it("should authenticate network with open AP and WPA AP", function()
    local mock_cli = {
      addNetwork = function() return 1 end,
      setNetwork = function() return "OK" end,
      removeNetwork = function() return "OK" end,
      enableNetworkByID = function() return "OK" end,
      attach = function() end,
      getConnectedNetwork = function()
        return { id = 1, ssid = "TestNet" }
      end,
      readEvent = function() return nil end,
      waitForEvent = function() end,
      close = function() end,
    }

    stub(mock_wpaclient, "new", function() return mock_cli end)
    stub(WpaSupplicant, "saveNetwork", function() end)

    local success, msg = WpaSupplicant:authenticateNetwork({
      ssid = "TestNet",
      password = "",
    })
    assert.is_true(success)

    local success_wpa, _ = WpaSupplicant:authenticateNetwork({
      ssid = "TestNet",
      password = "secretpassword",
    })
    assert.is_true(success_wpa)

    WpaSupplicant.saveNetwork:revert()
    mock_wpaclient.new:revert()
  end)

  it("should disconnect network by wpa_supplicant_id", function()
    local removed_id = nil
    local mock_cli = {
      removeNetwork = function(self, id) removed_id = id; return "OK" end,
      close = function() end,
    }

    stub(mock_wpaclient, "new", function() return mock_cli end)

    WpaSupplicant:disconnectNetwork({ wpa_supplicant_id = 42 })
    assert.are.equal(42, removed_id)

    mock_wpaclient.new:revert()
  end)
end)
