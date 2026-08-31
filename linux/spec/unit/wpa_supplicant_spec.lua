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
    WpaSupplicant.wpa_supplicant =
      { ctrl_interface = "/var/run/wpa_supplicant" }
  end)

  it("should expose WpaSupplicant helper module", function()
    assert.is_table(WpaSupplicant)
  end)

  it(
    "should handle error when WpaClient fails to initialize in getNetworkList",
    function()
      stub(mock_wpaclient, "new", function()
        return nil, "Control socket failed"
      end)

      local list, err = WpaSupplicant:getNetworkList()
      assert.is_nil(list)
      assert.is_not_nil(err)

      mock_wpaclient.new:revert()
    end
  )

  it(
    "should handle scanning results with saved networks and decoded SSIDs",
    function()
      local mock_nw = {
        ssid = "\\x54\\x65\\x73\\x74", -- "Test"
        bssid = "00:11:22:33:44:55",
        getSignalQuality = function()
          return 80
        end,
      }

      local mock_cli = {
        scanThenGetResults = function()
          return { mock_nw }
        end,
        close = function() end,
      }

      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)
      stub(WpaSupplicant, "getAllSavedNetworks", function()
        return {
          read = function()
            return { password = "pass", psk = "123456" }
          end,
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
    end
  )

  it("should authenticate network with open AP and WPA AP", function()
    local mock_cli = {
      addNetwork = function()
        return 1
      end,
      setNetwork = function()
        return "OK"
      end,
      removeNetwork = function()
        return "OK"
      end,
      enableNetworkByID = function()
        return "OK"
      end,
      attach = function() end,
      getConnectedNetwork = function()
        return { id = 1, ssid = "TestNet" }
      end,
      readEvent = function()
        return nil
      end,
      waitForEvent = function() end,
      close = function() end,
    }

    stub(mock_wpaclient, "new", function()
      return mock_cli
    end)
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
      removeNetwork = function(self, id)
        removed_id = id
        return "OK"
      end,
      close = function() end,
    }

    stub(mock_wpaclient, "new", function()
      return mock_cli
    end)

    WpaSupplicant:disconnectNetwork({ wpa_supplicant_id = 42 })
    assert.are.equal(42, removed_id)

    mock_wpaclient.new:revert()
  end)

  it("should handle forgetting network", function()
    local mock_settings = {
      del = function() end,
      save = function() end,
    }
    stub(WpaSupplicant, "getAllSavedNetworks", function()
      return mock_settings
    end)

    if type(WpaSupplicant.forgetNetwork) == "function" then
      WpaSupplicant:forgetNetwork({ ssid = "TestNet" })
    end

    WpaSupplicant.getAllSavedNetworks:revert()
  end)

  describe("WpaSupplicant Initialization and Network Queries", function()
    it("initializes network manager bindings via WpaSupplicant.init", function()
      local mock_mgr = {}
      WpaSupplicant.init(mock_mgr, { ctrl_interface = "/var/run/wpa_test" })
      assert.is_equal("/var/run/wpa_test", mock_mgr.wpa_supplicant.ctrl_interface)
      assert.is_equal(WpaSupplicant.getNetworkList, mock_mgr.getNetworkList)
      assert.is_equal(WpaSupplicant.getCurrentNetwork, mock_mgr.getCurrentNetwork)
      assert.is_equal(WpaSupplicant.authenticateNetwork, mock_mgr.authenticateNetwork)
      assert.is_equal(WpaSupplicant.disconnectNetwork, mock_mgr.disconnectNetwork)
      assert.is_equal(WpaSupplicant.getConfiguredNetworks, mock_mgr.getConfiguredNetworks)
    end)

    it("retrieves configured networks via getConfiguredNetworks", function()
      local mock_cli = {
        listNetworks = function()
          return { { id = 0, ssid = "ConfiguredNet" } }
        end,
        close = function() end,
      }
      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)

      local list, err = WpaSupplicant:getConfiguredNetworks()
      assert.is_table(list)
      assert.is_equal("ConfiguredNet", list[1].ssid)
      assert.is_nil(err)

      mock_wpaclient.new:revert()
    end)

    it("retrieves current network with decoded SSID and fallback", function()
      local mock_cli = {
        getConnectedNetwork = function()
          return nil, "Not connected"
        end,
        getCurrentNetwork = function()
          return { id = 2, ssid = "\\x57\\x69\\x46\\x69" } -- "WiFi"
        end,
        close = function() end,
      }
      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)

      local curr = WpaSupplicant:getCurrentNetwork()
      assert.is_table(curr)
      assert.is_equal("WiFi", curr.ssid)
      assert.is_equal(2, curr.id)

      mock_wpaclient.new:revert()
    end)

    it("handles authentication failure when setNetwork fails", function()
      local mock_cli = {
        addNetwork = function()
          return 1
        end,
        setNetwork = function()
          return "FAIL"
        end,
        removeNetwork = function()
          return "OK"
        end,
        close = function() end,
      }
      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)

      local success, msg = WpaSupplicant:authenticateNetwork({
        ssid = "FailingNet",
        password = "pwd",
      })
      assert.is_false(success)
      assert.is_truthy(msg:find("error occurred", 1, true))

      mock_wpaclient.new:revert()
    end)

    it("handles auth events with auth failure limit and timeouts", function()
      local event_idx = 0
      local mock_cli = {
        addNetwork = function() return 1 end,
        setNetwork = function() return "OK" end,
        enableNetworkByID = function() return "OK" end,
        attach = function() end,
        getConnectedNetwork = function() return nil end,
        readEvent = function()
          event_idx = event_idx + 1
          return {
            isScanEvent = function() return false end,
            isAuthSuccessful = function() return false end,
            isAuthFailed = function() return true end,
            msg = "Auth failed",
          }
        end,
        waitForEvent = function() end,
        removeNetwork = function() return "OK" end,
        close = function() end,
      }
      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)
      stub(WpaSupplicant, "saveNetwork", function() end)

      local success, msg = WpaSupplicant:authenticateNetwork({
        ssid = "BadPwdNet",
        password = "wrong",
      })
      assert.is_false(success)
      assert.is_equal("Failed to authenticate", msg)

      WpaSupplicant.saveNetwork:revert()
      mock_wpaclient.new:revert()
    end)
  end)
end)
