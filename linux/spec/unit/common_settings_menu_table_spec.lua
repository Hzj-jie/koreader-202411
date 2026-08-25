describe("Common Settings Menu Table Spec", function()
  local common_settings
  local Device
  local DocSettings
  local Event
  local InfoMessage
  local UIManager
  local Screen

  setup(function()
    require("commonrequire")
    Device = require("device")
    DocSettings = require("docsettings")
    Event = require("ui/event")
    InfoMessage = require("ui/widget/infomessage")
    UIManager = require("ui/uimanager")
    Screen = Device.screen
    common_settings = require("ui/elements/common_settings_menu_table")
  end)

  it("should provide top-level menu definitions", function()
    assert.is_table(common_settings)
    assert.is_table(common_settings.network)
    assert.is_table(common_settings.screen)
    assert.is_table(common_settings.navigation)
    assert.is_table(common_settings.document)
    assert.is_table(common_settings.device)
  end)

  it("should handle night mode toggles and event broadcasts", function()
    assert.is_table(common_settings.night_mode)
    G_reader_settings:save("night_mode", false)
    assert.is_false(common_settings.night_mode.checked_func())

    local broadcast_events = {}
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      table.insert(broadcast_events, ev)
    end

    common_settings.night_mode.callback()
    assert.is_true(#broadcast_events > 0)
    assert.are_equal("onToggleNightMode", broadcast_events[1].handler)

    G_reader_settings:save("night_mode", true)
    assert.is_true(common_settings.night_mode.checked_func())
    UIManager.broadcastEvent = orig_broadcast
  end)

  it("should handle frontlight dialog callback if available", function()
    if common_settings.frontlight then
      local broadcast_events = {}
      local orig_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(self, ev)
        table.insert(broadcast_events, ev)
      end
      common_settings.frontlight.callback()
      assert.is_true(#broadcast_events > 0)
      assert.are_equal("onShowFlDialog", broadcast_events[1].handler)
      UIManager.broadcastEvent = orig_broadcast
    end
  end)

  it("should handle charging LED and sleepcover options", function()
    if common_settings.charging_led then
      G_reader_settings:save("enable_charging_led", true)
      assert.is_true(common_settings.charging_led.checked_func())
      common_settings.charging_led.callback()
      assert.is_false(common_settings.charging_led.checked_func())
    end

    local orig_ask = UIManager.askForRestart
    local asked = false
    UIManager.askForRestart = function()
      asked = true
    end

    if common_settings.ignore_sleepcover then
      G_reader_settings:save("ignore_power_sleepcover", false)
      assert.is_false(common_settings.ignore_sleepcover.checked_func())
      common_settings.ignore_sleepcover.callback()
      assert.is_true(G_reader_settings:isTrue("ignore_power_sleepcover"))
      assert.is_true(asked)
    end

    if common_settings.ignore_open_sleepcover then
      asked = false
      G_reader_settings:save("ignore_open_sleepcover", false)
      assert.is_false(common_settings.ignore_open_sleepcover.checked_func())
      common_settings.ignore_open_sleepcover.callback()
      assert.is_true(G_reader_settings:isTrue("ignore_open_sleepcover"))
      assert.is_true(asked)
    end
    UIManager.askForRestart = orig_ask
  end)

  it("should handle taps and gestures ignore hold corners", function()
    if common_settings.ignore_hold_corners then
      G_reader_settings:save("ignore_hold_corners", false)
      assert.is_false(common_settings.ignore_hold_corners.checked_func())

      local broadcast_events = {}
      local orig_broadcast = UIManager.broadcastEvent
      UIManager.broadcastEvent = function(self, ev)
        table.insert(broadcast_events, ev)
      end
      common_settings.ignore_hold_corners.callback()
      assert.is_true(#broadcast_events > 0)
      assert.are_equal("onIgnoreHoldCorners", broadcast_events[1].handler)
      UIManager.broadcastEvent = orig_broadcast
    end
  end)

  it("should handle disable out of order input tap setting", function()
    assert.is_table(common_settings.disable_out_of_order_tap)
    G_reader_settings:save("disable_out_of_order_input", true)
    assert.is_true(common_settings.disable_out_of_order_tap.checked_func())
    common_settings.disable_out_of_order_tap.callback()
    assert.is_false(common_settings.disable_out_of_order_tap.checked_func())
    common_settings.disable_out_of_order_tap.callback()
    assert.is_true(common_settings.disable_out_of_order_tap.checked_func())
  end)

  it("should handle navigation back_to_exit settings", function()
    assert.is_table(common_settings.back_to_exit)
    assert.is_string(common_settings.back_to_exit.text_func())

    for _, item in ipairs(common_settings.back_to_exit.sub_item_table) do
      item.callback()
      assert.is_true(item.checked_func())
    end
  end)

  it("should handle navigation back_in_filemanager settings", function()
    assert.is_table(common_settings.back_in_filemanager)
    assert.is_string(common_settings.back_in_filemanager.text_func())

    for _, item in ipairs(common_settings.back_in_filemanager.sub_item_table) do
      if item.text_func then
        assert.is_string(item.text_func())
      end
      item.callback()
      assert.is_true(item.checked_func())
    end
  end)

  it("should handle navigation back_in_reader settings", function()
    assert.is_table(common_settings.back_in_reader)
    assert.is_string(common_settings.back_in_reader.text_func())

    for _, item in ipairs(common_settings.back_in_reader.sub_item_table) do
      if item.text_func then
        assert.is_string(item.text_func())
      end
      item.callback()
      assert.is_true(item.checked_func())
    end
  end)

  it(
    "should handle opening_page_location_stack and skim_dialog_position",
    function()
      assert.is_table(common_settings.opening_page_location_stack)
      G_reader_settings:save("opening_page_location_stack", false)
      assert.is_false(
        common_settings.opening_page_location_stack.checked_func()
      )
      common_settings.opening_page_location_stack.callback()
      assert.is_true(common_settings.opening_page_location_stack.checked_func())

      assert.is_table(common_settings.skim_dialog_position)
      assert.is_string(common_settings.skim_dialog_position.text_func())
      for _, item in ipairs(common_settings.skim_dialog_position.sub_item_table) do
        item.callback()
        assert.is_true(item.checked_func())
      end
    end
  )

  it(
    "should handle document metadata location submenu and callbacks",
    function()
      assert.is_table(common_settings.document_metadata_location)
      assert.is_string(common_settings.document_metadata_location.text_func())

      local shown = {}
      local orig_show = UIManager.show
      UIManager.show = function(self, widget)
        table.insert(shown, widget)
      end

      for _, item in
        ipairs(common_settings.document_metadata_location.sub_item_table)
      do
        if item.text_func then
          assert.is_string(item.text_func())
        end
        if item.enabled_func then
          item.enabled_func()
        end
        if item.callback then
          item.callback()
        end
      end

      -- Test switching between doc, dir, and hash locations
      G_reader_settings:save("document_metadata_folder", "doc")
      for _, item in
        ipairs(common_settings.document_metadata_location.sub_item_table)
      do
        if item.checked_func and item.radio then
          item.callback()
        end
      end

      UIManager.show = orig_show
    end
  )

  it("should handle document auto save and end of document actions", function()
    assert.is_table(common_settings.document_auto_save)
    assert.is_string(common_settings.document_auto_save.help_text)
    G_reader_settings:save("auto_save_settings", true)
    assert.is_true(common_settings.document_auto_save.checked_func())
    common_settings.document_auto_save.callback()
    assert.is_false(common_settings.document_auto_save.checked_func())

    assert.is_table(common_settings.document_end_action)
    for _, item in ipairs(common_settings.document_end_action.sub_item_table) do
      if item.enabled_func then
        item.enabled_func()
      end
      item.callback()
      if item.checked_func then
        item.checked_func()
      end
    end
  end)

  it("should handle dimension units settings and callbacks", function()
    assert.is_table(common_settings.units)
    assert.is_string(common_settings.units.text_func())
    for _, item in ipairs(common_settings.units.sub_item_table) do
      if item.enabled_func then
        item.enabled_func()
      end
      item.callback()
      if item.checked_func then
        item.checked_func()
      end
    end
  end)

  it("should handle screenshot folder callback", function()
    assert.is_table(common_settings.screenshot)
    local Screenshoter = require("ui/widget/screenshoter")
    local orig_choose = Screenshoter.chooseFolder
    local called = false
    Screenshoter.chooseFolder = function()
      called = true
    end
    common_settings.screenshot.callback()
    assert.is_true(called)
    Screenshoter.chooseFolder = orig_choose
  end)
end)
