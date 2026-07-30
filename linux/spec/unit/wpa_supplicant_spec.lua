local stub = require("luassert.stub")

describe("WpaSupplicant network module", function()
  local WpaSupplicant
  local mock_wpaclient

  setup(function()
    require("commonrequire")

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
    "should handle error when WpaClient fails in scanThenGetResults",
    function()
      local mock_cli = {
        scanThenGetResults = function()
          return nil, "Scan error"
        end,
        close = function() end,
      }
      stub(mock_wpaclient, "new", function()
        return mock_cli
      end)

      local list, err = WpaSupplicant:getNetworkList()
      assert.is_nil(list)
      assert.is_not_nil(err)

      mock_wpaclient.new:revert()
    end
  )

  it("should handle error handling when disconnecting or getting current network", function()
    if type(WpaSupplicant.disconnectNetwork) == "function" then
      local ok, err = WpaSupplicant:disconnectNetwork({ ssid = "test_ssid" })
      assert.is_nil(ok)
    end
  end)
end)
