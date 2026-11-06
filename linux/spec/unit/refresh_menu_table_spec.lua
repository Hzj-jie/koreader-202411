describe("Refresh Menu Table Spec", function()
  local RefreshMenuTable
  local UIManager

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    RefreshMenuTable = require("ui/elements/refresh_menu_table")
  end)

  it("should provide refresh menu items and about callback", function()
    assert.is_table(RefreshMenuTable)
    assert.is_true(#RefreshMenuTable >= 5)

    local shown = false
    local orig_show = UIManager.show
    UIManager.show = function()
      shown = true
    end

    RefreshMenuTable[1].callback()
    assert.is_true(shown)
    UIManager.show = orig_show
  end)

  it(
    "should handle refresh rate selection callbacks and checked_funcs",
    function()
      local events = {}
      local orig_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(self, ev)
        table.insert(events, ev)
      end

      for i = 2, 5 do
        local item = RefreshMenuTable[i]
        assert.is_table(item)
        assert.is_boolean(item.checked_func())
        item.callback()
        assert.is_true(#events > 0)
        assert.are_equal("onSetRefreshRate", events[#events].handler)
      end

      UIManager.broadcastEvent = orig_broadcast
    end
  )

  it("should decouple balanced refresh rate from device default", function()
    local Device = require("device")
    local named_settings = require("named_settings")
    local orig_isKindle = Device.isKindle
    local orig_broadcast = UIManager.broadcastEvent
    local broadcast_events = {}
    finally(function()
      Device.isKindle = orig_isKindle
      UIManager.broadcastEvent = orig_broadcast
      G_reader_settings:delete("full_refresh_count")
    end)
    UIManager.broadcastEvent = function(self, ev)
      table.insert(broadcast_events, ev)
    end

    Device.isKindle = function()
      return true
    end
    assert.are_equal(0, named_settings.default.full_refresh_count())
    assert.are_equal(0, named_settings.full_refresh_count())

    local never_item = RefreshMenuTable[2]
    local balance_item = RefreshMenuTable[4]

    assert.is_true(never_item.checked_func())
    assert.is_false(balance_item.checked_func())

    balance_item.callback()
    assert.are_equal(1, #broadcast_events)
    assert.are_equal("onSetRefreshRate", broadcast_events[1].handler)
    assert.are_equal(24, broadcast_events[1].args[1])

    named_settings.set.full_refresh_count(24)
    assert.is_false(never_item.checked_func())
    assert.is_true(balance_item.checked_func())
  end)
end)
