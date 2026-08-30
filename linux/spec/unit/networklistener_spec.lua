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

    listener:onPendingConnected(function()
      cb_connected_called = true
    end, "job1")

    listener:onPendingOnline(function()
      cb_online_called = true
    end, "job2")

    assert.are.equal("1 / 1", listener:countsOfPendingJobs())

    local c_keys, o_keys = listener:pendingJobKeys()
    assert.are.same({ "job1" }, c_keys)
    assert.are.same({ "job2" }, o_keys)

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
    "should automatically fingerprint and deduplicate identical closures without explicit key",
    function()
      local listener = NetworkListener:new()

      local count = 0
      local target = "doc1.epub"
      local function make_callback()
        return function()
          count = count + 1
          return target
        end
      end

      local cb1 = make_callback()
      local cb2 = make_callback()

      listener:onPendingOnline(cb1)
      listener:onPendingOnline(cb2)

      -- Both closures capture identical upvalues, so only 1 pending job is recorded
      assert.are.equal("0 / 1", listener:countsOfPendingJobs())

      listener:onNetworkOnline()
      assert.are.equal(1, count)
    end
  )

  it(
    "should distinguish closures with different upvalues when key is omitted",
    function()
      local listener = NetworkListener:new()

      local function make_callback(doc)
        return function()
          return doc
        end
      end

      local cb_a = make_callback("book_a.epub")
      local cb_b = make_callback("book_b.epub")

      listener:onPendingOnline(cb_a)
      listener:onPendingOnline(cb_b)

      -- Capturing distinct parameters creates distinct keys
      assert.are.equal("0 / 2", listener:countsOfPendingJobs())

      listener:onNetworkOnline()
    end
  )
end)
