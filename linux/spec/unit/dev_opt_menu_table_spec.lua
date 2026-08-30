describe("DevOptMenuTable element", function()
  local DevOptMenuTable
  local UIManager
  local Device
  local dbg

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    Device = require("device")
    dbg = require("dbg")
    DevOptMenuTable = require("ui/elements/dev_opt_menu_table")
  end)

  it("should return a valid developer menu options table", function()
    assert.is_table(DevOptMenuTable)
    assert.is_string(DevOptMenuTable.text)
    assert.is_table(DevOptMenuTable.sub_item_table)
  end)

  local function find_item(text)
    for _, item in ipairs(DevOptMenuTable.sub_item_table) do
      if item.text == text then
        return item
      end
    end
  end

  it("should handle Clear caches callback", function()
    local item = find_item("Clear caches")
    assert.is_not_nil(item)

    local shown_widget
    local orig_show = UIManager.show
    local orig_ask = UIManager.askForRestart
    local asked_restart = false
    UIManager.show = function(self, w)
      shown_widget = w
    end
    UIManager.askForRestart = function()
      asked_restart = true
    end

    item.callback()
    assert.is_not_nil(shown_widget)
    assert.is_function(shown_widget.ok_callback)

    shown_widget.ok_callback()
    assert.is_true(asked_restart)

    UIManager.show = orig_show
    UIManager.askForRestart = orig_ask
  end)

  it("should handle debug logging toggles", function()
    local item_dbg = find_item("Enable debug logging")
    assert.is_not_nil(item_dbg)

    G_reader_settings:makeFalse("debug")
    assert.is_false(item_dbg.checked_func())

    item_dbg.callback()
    assert.is_true(G_reader_settings:isTrue("debug"))
    assert.is_true(item_dbg.checked_func())

    item_dbg.callback()
    assert.is_false(G_reader_settings:isTrue("debug"))
    assert.is_false(item_dbg.checked_func())
  end)

  it("should handle verbose debug logging toggles", function()
    local item_vdbg = find_item("Enable verbose debug logging")
    assert.is_not_nil(item_vdbg)

    G_reader_settings:makeFalse("debug")
    assert.is_false(item_vdbg.enabled_func())

    G_reader_settings:makeTrue("debug")
    assert.is_true(item_vdbg.enabled_func())

    G_reader_settings:makeFalse("debug_verbose")
    assert.is_false(item_vdbg.checked_func())

    item_vdbg.callback()
    assert.is_true(G_reader_settings:isTrue("debug_verbose"))
    assert.is_true(item_vdbg.checked_func())

    item_vdbg.callback()
    assert.is_false(G_reader_settings:isTrue("debug_verbose"))
    assert.is_false(item_vdbg.checked_func())
  end)

  it("should handle Disable C blitter item", function()
    local item = find_item("Disable C blitter")
    assert.is_not_nil(item)

    assert.is_boolean(item.enabled_func())
    assert.is_boolean(item.checked_func())

    local prev = G_reader_settings:isTrue("dev_no_c_blitter")
    item.callback()
    assert.are_not_equal(prev, G_reader_settings:isTrue("dev_no_c_blitter"))
    item.callback()
    assert.are.equal(prev, G_reader_settings:isTrue("dev_no_c_blitter"))
  end)

  it("should handle Anti-alias rounded corners toggle", function()
    local item = find_item("Anti-alias rounded corners")
    assert.is_not_nil(item)

    local prev = item.checked_func()
    item.callback()
    assert.are_not_equal(prev, item.checked_func())
    item.callback()
    assert.are.equal(prev, item.checked_func())
  end)

  it("should handle Disable enhanced UI text shaping (xtext)", function()
    local item = find_item("Disable enhanced UI text shaping (xtext)")
    assert.is_not_nil(item)

    local asked_restart = false
    local orig_ask = UIManager.askForRestart
    UIManager.askForRestart = function()
      asked_restart = true
    end

    local prev = item.checked_func()
    item.callback()
    assert.is_true(asked_restart)
    assert.are_not_equal(prev, item.checked_func())
    item.callback()
    assert.are.equal(prev, item.checked_func())

    UIManager.askForRestart = orig_ask
  end)

  it(
    "should handle UI layout mirroring and text direction sub-items",
    function()
      local item = find_item("UI layout mirroring and text direction")
      assert.is_not_nil(item)
      assert.is_table(item.sub_item_table)

      local asked_restart = false
      local orig_ask = UIManager.askForRestart
      UIManager.askForRestart = function()
        asked_restart = true
      end

      for _, sub in ipairs(item.sub_item_table) do
        assert.is_string(sub.text)
        local prev = sub.checked_func()
        sub.callback()
        assert.is_true(asked_restart)
        assert.are_not_equal(prev, sub.checked_func())
        sub.callback()
        assert.are.equal(prev, sub.checked_func())
      end

      UIManager.askForRestart = orig_ask
    end
  )

  it("should handle CRE call cache item and hold callback", function()
    local item
    for _, it in ipairs(DevOptMenuTable.sub_item_table) do
      if it.text_func and it.hold_callback then
        item = it
        break
      end
    end
    assert.is_not_nil(item)

    G_reader_settings:makeTrue("use_cre_call_cache")
    G_reader_settings:makeFalse("use_cre_call_cache_log_stats")
    assert.is_string(item.text_func())
    assert.is_true(item.checked_func())

    G_reader_settings:makeTrue("use_cre_call_cache_log_stats")
    assert.is_true(item.text_func():find("stats") ~= nil)

    item.callback()
    assert.is_false(item.checked_func())
    item.callback()
    assert.is_true(item.checked_func())

    local updated = false
    local mock_menu = {
      updateItems = function()
        updated = true
      end,
    }
    item.hold_callback(mock_menu)
    assert.is_true(updated)
  end)

  it("should handle Dump the fontlist cache callback", function()
    local item = find_item("Dump the fontlist cache")
    assert.is_not_nil(item)
    item.callback()
  end)

  it(
    "should dynamically load platform-specific options under different devices",
    function()
      -- Test device-specific branches by reloading module under simulated device environments
      local orig_is_kobo = Device.isKobo
      local orig_is_sunxi = Device.isSunxi
      local orig_has_color = Device.hasColorScreen
      local orig_has_eink = Device.hasEinkScreen
      local orig_can_hw_dither = Device.canHWDither
      local orig_is_remarkable = Device.isRemarkable
      local orig_is_pocketbook = Device.isPocketBook
      local orig_is_android = Device.isAndroid
      local orig_can_toggle_led = Device.canToggleChargingLED
      local orig_is_b288 = Device.isB288SoC
      local orig_has_reliable_wait = Device.hasReliableMxcWaitFor

      Device.isKobo = function()
        return true
      end
      Device.isSunxi = function()
        return false
      end
      Device.hasColorScreen = function()
        return true
      end
      Device.hasEinkScreen = function()
        return true
      end
      Device.canHWDither = function()
        return true
      end
      Device.isRemarkable = function()
        return true
      end
      Device.isPocketBook = function()
        return true
      end
      Device.isAndroid = function()
        return true
      end
      Device.canToggleChargingLED = function()
        return true
      end
      Device.isB288SoC = function()
        return true
      end
      Device.hasReliableMxcWaitFor = function()
        return false
      end
      Device.test = function() end

      package.loaded["ui/elements/dev_opt_menu_table"] = nil
      local custom_menu = require("ui/elements/dev_opt_menu_table")
      assert.is_table(custom_menu)

      -- Exercise the newly added device-specific items
      for _, it in ipairs(custom_menu.sub_item_table) do
        if it.checked_func then
          pcall(it.checked_func)
        end
        if it.enabled_func then
          pcall(it.enabled_func)
        end
        if it.callback then
          pcall(it.callback)
        end
      end

      -- Restore
      Device.isKobo = orig_is_kobo
      Device.isSunxi = orig_is_sunxi
      Device.hasColorScreen = orig_has_color
      Device.hasEinkScreen = orig_has_eink
      Device.canHWDither = orig_can_hw_dither
      Device.isRemarkable = orig_is_remarkable
      Device.isPocketBook = orig_is_pocketbook
      Device.isAndroid = orig_is_android
      Device.canToggleChargingLED = orig_can_toggle_led
      Device.isB288SoC = orig_is_b288
      Device.hasReliableMxcWaitFor = orig_has_reliable_wait
      package.loaded["ui/elements/dev_opt_menu_table"] = nil
    end
  )
end)
