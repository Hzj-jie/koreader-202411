describe("AutoSuspend main plugin module", function()
  local AutoSuspend, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    local old_canSuspend = Device.canSuspend
    Device.canSuspend = function()
      return true
    end

    AutoSuspend = require("plugins/autosuspend.koplugin/main")
    Device.canSuspend = old_canSuspend
  end)

  it("should initialize AutoSuspend plugin and check enabled flags", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    assert.is_table(inst)
    assert.is_boolean(inst:_enabled())
  end)

  it(
    "should add AutoSuspend configuration items to main menu and trigger callbacks",
    function()
      local UIManager = require("ui/uimanager")
      local orig_show = UIManager.show
      local shown_widgets = {}
      UIManager.show = function(self_uim, widget)
        table.insert(shown_widgets, widget)
      end

      local mock_menu = { updateItems = function() end }
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }

      local inst = AutoSuspend:new({ ui = mock_ui })
      local menu_items = {}
      inst:addToMainMenu(menu_items)

      assert.is_table(menu_items.autosuspend)
      assert.is_string(menu_items.autosuspend.text_func())
      menu_items.autosuspend.callback(mock_menu)
      local autosuspend_spinner = shown_widgets[#shown_widgets]
      assert.is_table(autosuspend_spinner)
      if autosuspend_spinner and autosuspend_spinner.callback then
        autosuspend_spinner.callback({ hour = 1, min = 30 })
        assert.are.equal(5400, inst.auto_suspend_timeout_seconds)
      end
      if autosuspend_spinner and autosuspend_spinner.default_callback then
        autosuspend_spinner.default_callback()
      end
      if autosuspend_spinner and autosuspend_spinner.extra_callback then
        autosuspend_spinner.extra_callback({ onExit = function() end })
        assert.are.equal(-1, inst.auto_suspend_timeout_seconds)
      end

      UIManager.show = orig_show
    end
  )

  it("should schedule suspend tasks and handle lifecycle events safely", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = AutoSuspend:new({ ui = mock_ui })
    inst:_schedule()
    inst:_unschedule()
    inst:onSuspend()
    inst:onResume()
    inst:onClose()
  end)
end)
