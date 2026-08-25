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
end)
