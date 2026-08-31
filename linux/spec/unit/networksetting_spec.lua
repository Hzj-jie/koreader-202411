describe("NetworkSetting module", function()
  local NetworkSetting, NetworkMgr, UIManager
  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    NetworkSetting = require("ui/widget/networksetting")
    NetworkMgr = require("ui/network/manager")
  end)

  it("should initialize properly with empty network list", function()
    local ns = NetworkSetting:new({ network_list = {} })
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
    local ns = NetworkSetting:new({
      network_list = network_list,
      connect_callback = function()
        called = true
      end,
    })
    assert.equal("Wi-Fi networks (1/1)", ns[1][1][1][1].title_widget.text)
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
    local ns = NetworkSetting:new({
      network_list = network_list,
      disconnect_callback = function()
        called = true
      end,
    })
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
    local ns = NetworkSetting:new({ network_list = network_list })
    assert.is.same("foo", ns.connected_item.info.ssid)
    ns.connected_item:disconnect()
    assert.is.falsy(ns.connected_item)

    NetworkMgr.disconnectNetwork:revert()
    NetworkMgr.releaseIP:revert()
  end)

  it(
    "should show 'Obtaining IP...' message and call NetworkMgr:obtainIP on successful authentication",
    function()
      stub(NetworkMgr, "authenticateNetwork", function()
        return true
      end)
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
      local ns = NetworkSetting:new({ network_list = network_list })
      local item = ns[1][1][1][3].items[1]

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
    end
  )

  it(
    "should be placed above modal widgets in the UIManager window stack",
    function()
      local Widget = require("ui/widget/widget")
      local Geom = require("ui/geometry")
      local mock_modal = Widget:new({
        modal = true,
        dimen = Geom:new({ w = 100, h = 100 }),
      })
      local ns = NetworkSetting:new({ network_list = {} })

      UIManager:show(mock_modal)
      UIManager:show(ns)

      local modal_idx, ns_idx
      for idx, win in ipairs(UIManager._window_stack) do
        if win.widget == mock_modal then
          modal_idx = idx
        elseif win.widget == ns then
          ns_idx = idx
        end
      end

      -- Clean up UIManager stack first
      UIManager:close(ns)
      UIManager:close(mock_modal)

      assert.is_not_nil(modal_idx, "mock_modal should be in the window stack")
      assert.is_not_nil(ns_idx, "NetworkSetting should be in the window stack")
      assert.is_true(
        ns_idx > modal_idx,
        "NetworkSetting should be above mock_modal in the stack"
      )
    end
  )

  it(
    "should close self and call NetworkMgr:showNetworkMenu when title bar refresh button is tapped",
    function()
      stub(NetworkMgr, "showNetworkMenu")
      spy.on(UIManager, "close")

      local ns = NetworkSetting:new({
        network_list = {},
        connect_callback = "mock_callback",
      })

      local title_bar = ns[1][1][1][1]
      title_bar.right_icon_tap_callback()

      assert.spy(UIManager.close).was.called_with(UIManager, ns)
      assert
        .spy(NetworkMgr.showNetworkMenu).was
        .called_with(NetworkMgr, "mock_callback")

      NetworkMgr.showNetworkMenu:revert()
      UIManager.close:revert()
    end
  )

  it("handles MinimalPaginator painting and setProgress", function()
    local Blitbuffer = require("ffi/blitbuffer")
    local ns = NetworkSetting:new({ network_list = {} })
    local paginator = ns.pagination
    assert.is_not_nil(paginator)

    paginator:setProgress(0.5)
    assert.are.equal(0.5, paginator.progress)

    local bb = Blitbuffer.new(100, 20)
    assert.has_no.errors(function()
      paginator:paintTo(bb, 0, 0)
    end)
  end)

  it("handles NetworkItem onTapSelect, WEP check, edit, add, and saveAndConnectToNetwork", function()
    stub(NetworkMgr, "saveNetwork")
    stub(NetworkMgr, "deleteNetwork")
    stub(NetworkMgr, "authenticateNetwork", function() return true end)
    stub(NetworkMgr, "obtainIP")

    local network_list = {
      {
        ssid = "wep_net",
        signal_level = -50,
        flags = "[WEP][ESS]",
        signal_quality = 90,
      },
      {
        ssid = "wpa_net",
        signal_level = -60,
        flags = "[WPA2-PSK-CCMP][ESS]",
        signal_quality = 60,
        password = "secret_password",
      },
      {
        ssid = "open_net",
        signal_level = -70,
        flags = "[ESS]",
        signal_quality = 20,
      },
    }

    local ns = NetworkSetting:new({ network_list = network_list })
    local items = ns[1][1][1][3].items
    local wep_item = items[1]
    local wpa_item = items[2]
    local open_item = items[3]

    -- Test WEP onTapSelect
    local shown_widget
    wep_item.showWidget = function(self, w) shown_widget = w end
    wep_item:onTapSelect(nil, {})
    assert.is_not_nil(shown_widget)

    -- Test WPA onTapSelect edit button tap
    local edit_dialog
    wpa_item.showWidget = function(self, w) edit_dialog = w end
    wpa_item:onTapSelect(nil, { pos = wpa_item.btn_edit_nw.dimen })
    assert.is_not_nil(edit_dialog)

    -- Test forget button in edit_dialog
    local forget_btn = edit_dialog.buttons[1][2]
    forget_btn.callback()
    assert.stub(NetworkMgr.deleteNetwork).was_called()

    -- Test open net onAddNetwork
    local add_dialog
    open_item.showWidget = function(self, w) add_dialog = w end
    open_item:onTapSelect(nil, {})
    assert.is_not_nil(add_dialog)

    -- Test saveAndConnectToNetwork with empty password on WPA
    local mock_pw_input = {
      getInputText = function() return "" end,
    }
    wep_item.info.flags = "[WPA2-PSK-CCMP][ESS]"
    wep_item:saveAndConnectToNetwork(mock_pw_input)

    -- Test saveAndConnectToNetwork with valid password
    local mock_valid_pw = {
      getInputText = function() return "new_valid_password" end,
    }
    wpa_item:saveAndConnectToNetwork(mock_valid_pw)
    assert.stub(NetworkMgr.saveNetwork).was_called()

    NetworkMgr.saveNetwork:revert()
    NetworkMgr.deleteNetwork:revert()
    NetworkMgr.authenticateNetwork:revert()
    NetworkMgr.obtainIP:revert()
  end)

  it("handles onTapClose and onClose", function()
    local Geom = require("ui/geometry")
    local ns = NetworkSetting:new({ network_list = {} })

    -- Inside popup
    local inside_ev = { pos = ns.popup.dimen }
    assert.is_nil(ns:onTapClose(nil, inside_ev))

    -- Outside popup
    local outside_ev = { pos = Geom:new({ x = -100, y = -100 }) }
    assert.is_true(ns:onTapClose(nil, outside_ev))

    -- onClose resets pending connection
    NetworkMgr.pending_connectivity_check = nil
    NetworkMgr.pending_connection = true
    ns:onClose()
    assert.is_false(NetworkMgr.pending_connection)
  end)
end)
