describe("Screen DPI Menu Table Spec", function()
  local ScreenDPIMenuTable
  local Device
  local Screen
  local UIManager

  setup(function()
    require("commonrequire")
    Device = require("device")
    Screen = Device.screen
    UIManager = require("ui/uimanager")
    ScreenDPIMenuTable = require("ui/elements/screen_dpi_menu_table")
  end)

  it("should provide valid Screen DPI menu table and subitems", function()
    assert.is_table(ScreenDPIMenuTable)
    assert.is_string(ScreenDPIMenuTable.text)
    assert.is_table(ScreenDPIMenuTable.sub_item_table)
    assert.is_true(#ScreenDPIMenuTable.sub_item_table >= 7)
  end)

  it("should handle Auto DPI selection and callbacks", function()
    local auto_item = ScreenDPIMenuTable.sub_item_table[1]
    assert.is_table(auto_item)
    assert.is_string(auto_item.text)
    assert.is_string(auto_item.help_text)

    local restart_asked = false
    local orig_ask = UIManager.askForRestart
    UIManager.askForRestart = function()
      restart_asked = true
    end

    auto_item.callback()
    assert.is_true(restart_asked)
    assert.is_boolean(auto_item.checked_func())

    UIManager.askForRestart = orig_ask
  end)

  it(
    "should handle predefined DPI items callbacks and checked functions",
    function()
      local restart_asked = false
      local orig_ask = UIManager.askForRestart
      UIManager.askForRestart = function()
        restart_asked = true
      end

      for i = 2, 7 do
        local item = ScreenDPIMenuTable.sub_item_table[i]
        assert.is_table(item)
        assert.is_string(item.text)
        assert.is_boolean(item.checked_func())
        item.callback()
        assert.is_true(restart_asked)
        restart_asked = false
      end

      UIManager.askForRestart = orig_ask
    end
  )

  it(
    "should handle Custom DPI menu item callbacks and hold_callback with SpinWidget",
    function()
      local custom_item = ScreenDPIMenuTable.sub_item_table[8]
      assert.is_table(custom_item)
      assert.is_string(custom_item.text_func())
      assert.is_falsy(custom_item.checked_func())

      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local dummy_menu = { updateItems = function() end }

      G_reader_settings:save("custom_screen_dpi", nil)
      custom_item.callback(dummy_menu)
      assert.is_table(shown_widget)
      if shown_widget.callback then
        shown_widget.callback({ value = 300 })
      end

      G_reader_settings:save("custom_screen_dpi", 300)
      assert.is_string(custom_item.text_func())
      custom_item.callback(dummy_menu)
      custom_item.hold_callback(dummy_menu)

      UIManager.show = orig_show
    end
  )
end)
