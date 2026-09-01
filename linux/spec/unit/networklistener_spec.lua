describe("NetworkListener module", function()
  local NetworkListener, Device, NetworkMgr, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    NetworkMgr = require("ui/network/manager")
    UIManager = require("ui/uimanager")

    UIManager.nextTick = function(arg1, arg2)
      local callback = type(arg1) == "function" and arg1 or arg2
      if callback then
        callback()
      end
    end

    local old_hasWifiToggle = Device.hasWifiToggle
    Device.hasWifiToggle = function()
      return true
    end

    NetworkListener = require("ui/network/networklistener")
    Device.hasWifiToggle = old_hasWifiToggle
  end)

  it("should register and report pending connection and online jobs", function()
    local listener = NetworkListener:new()

    local cb_connected_called = false
    local cb_online_called = false

    local job1 = function()
      cb_connected_called = true
    end

    local job2 = function()
      cb_online_called = true
    end

    listener:onPendingConnected(job1)
    listener:onPendingOnline(job2)

    assert.are.equal("1 / 1", listener:countsOfPendingJobs())

    local c_keys, o_keys = listener:pendingJobKeys()
    local util = require("util")
    assert.are.same({ util.functionFingerprint(job1) }, c_keys)
    assert.are.same({ util.functionFingerprint(job2) }, o_keys)

    listener:onNetworkConnected()
    assert.is_true(cb_connected_called)

    listener:onNetworkOnline()
    assert.is_true(cb_online_called)

    listener:onNetworkStateChanged()
  end)

  it("should handle Wi-Fi toggle and info events", function()
    local listener = NetworkListener:new()

    local old_isConnected = NetworkMgr.isConnected
    local old_toggleWifiOn = NetworkMgr.toggleWifiOn
    local old_toggleWifiOff = NetworkMgr.toggleWifiOff

    local toggled_on = false
    local toggled_off = false

    NetworkMgr.isConnected = function()
      return false
    end
    NetworkMgr.toggleWifiOn = function()
      toggled_on = true
    end
    NetworkMgr.toggleWifiOff = function()
      toggled_off = true
    end

    listener:onToggleWifi()
    assert.is_true(toggled_on)

    listener:onInfoWifiOff()
    assert.is_true(toggled_off)

    NetworkMgr.isConnected = old_isConnected
    NetworkMgr.toggleWifiOn = old_toggleWifiOn
    NetworkMgr.toggleWifiOff = old_toggleWifiOff
  end)

  it(
    "should automatically fingerprint and deduplicate identical closures without explicit keys",
    function()
      local listener = NetworkListener:new()

      local count1 = 0
      local count2 = 0

      local function makeTask(doc)
        return function()
          if doc == "docA" then
            count1 = count1 + 1
          else
            count2 = count2 + 1
          end
        end
      end

      -- Register same task closure twice without key
      listener:onPendingOnline(makeTask("docA"))
      listener:onPendingOnline(makeTask("docA"))

      -- Register different task closure without key
      listener:onPendingOnline(makeTask("docB"))

      -- Should have 2 unique pending jobs (docA deduped to 1, docB is 1)
      assert.are.equal("0 / 2", listener:countsOfPendingJobs())

      listener:onNetworkOnline()

      assert.is_equal(1, count1)
      assert.is_equal(1, count2)
      assert.are.equal("0 / 0", listener:countsOfPendingJobs())
    end
  )

  describe("Wi-Fi Activity Monitoring & Power Management", function()
    it("checks activity on 5M timer and toggles wifi off on idle", function()
      local listener = NetworkListener:new()
      local old_isTrue = G_reader_settings.isTrue
      local old_isWifiOn = NetworkMgr.isWifiOn
      local old_toggleWifiOff = NetworkMgr.toggleWifiOff

      local toggled_off = false
      G_reader_settings.isTrue = function(self, key)
        return key == "auto_disable_wifi"
      end
      NetworkMgr.isWifiOn = function()
        return true
      end
      NetworkMgr.toggleWifiOff = function()
        toggled_off = true
      end

      stub(listener, "_getTxPackets").returns(100)

      -- First check records initial packet count
      listener:onTimesChange_5M()
      assert.is_false(toggled_off)

      -- Second check with no activity (< margin) triggers toggleWifiOff
      listener._getTxPackets.returns(105)
      listener:onTimesChange_5M()
      assert.is_true(toggled_off)

      listener._getTxPackets:revert()
      G_reader_settings.isTrue = old_isTrue
      NetworkMgr.isWifiOn = old_isWifiOn
      NetworkMgr.toggleWifiOff = old_toggleWifiOff
    end)

    it("handles onInfoWifiOn when already connected", function()
      local listener = NetworkListener:new()
      stub(NetworkMgr, "isConnected").returns(true)
      stub(NetworkMgr, "getCurrentNetwork").returns({ ssid = "TestWiFi" })
      stub(UIManager, "show")

      listener:onInfoWifiOn()
      assert.stub(UIManager.show).was_called()

      -- When SSID is nil
      NetworkMgr.getCurrentNetwork.returns(nil)
      listener:onInfoWifiOn()
      assert.stub(UIManager.show).was_called()

      NetworkMgr.isConnected:revert()
      NetworkMgr.getCurrentNetwork:revert()
      UIManager.show:revert()
    end)

    it("handles onSuspend and onResume", function()
      local listener = NetworkListener:new()
      stub(Device, "hasWifiManager").returns(true)
      stub(NetworkMgr, "toggleWifiOff")

      listener:onSuspend()
      assert.stub(NetworkMgr.toggleWifiOff).was_called()

      Device.hasWifiManager:revert()
      NetworkMgr.toggleWifiOff:revert()
    end)

    it("handles onShowNetworkInfo for various network states", function()
      local listener = NetworkListener:new()
      stub(UIManager, "show")

      -- 1. Wi-Fi off
      stub(NetworkMgr, "isWifiOn").returns(false)
      listener:onShowNetworkInfo()
      assert.stub(UIManager.show).was_called()
      NetworkMgr.isWifiOn:revert()

      -- 2. Wi-Fi on, but disconnected -> calls reconnect
      stub(NetworkMgr, "isWifiOn").returns(true)
      stub(NetworkMgr, "isConnected").returns(false)
      stub(NetworkMgr, "reconnect")
      listener:onShowNetworkInfo()
      assert.stub(NetworkMgr.reconnect).was_called()
      NetworkMgr.reconnect:revert()

      -- 3. Connected with retrieveNetworkInfo available
      NetworkMgr.isConnected.returns(true)
      stub(Device, "retrieveNetworkInfo").returns({ "IP: 192.168.1.50" })
      stub(NetworkMgr, "queryOnlineState")
      stub(NetworkMgr, "isOnline").returns(true)
      stub(UIManager, "runWith").invokes(function(a, b)
        local callback = type(a) == "function" and a or b
        if callback then
          callback()
        end
      end)

      listener:onShowNetworkInfo()
      assert.stub(UIManager.show).was_called()

      NetworkMgr.isWifiOn:revert()
      NetworkMgr.isConnected:revert()
      Device.retrieveNetworkInfo:revert()
      NetworkMgr.queryOnlineState:revert()
      NetworkMgr.isOnline:revert()
      UIManager.runWith:revert()
      UIManager.show:revert()
    end)
  end)
end)
