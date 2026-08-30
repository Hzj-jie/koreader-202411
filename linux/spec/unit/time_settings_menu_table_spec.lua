describe("time_settings_menu_table module", function()
  local time_menu
  local UIManager
  local Device

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    Device = require("device")
    time_menu = require("ui/elements/time_settings_menu_table")
  end)

  it("should export menu structure with sub items", function()
    assert.is_table(time_menu)
    assert.is_string(time_menu.text)
    assert.is_table(time_menu.sub_item_table)
  end)

  it("should handle 12-hour clock toggles and event broadcast", function()
    local item_12h = time_menu.sub_item_table[1]
    assert.is_not_nil(item_12h)
    assert.is_function(item_12h.checked_func)

    local broadcasted
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      broadcasted = ev
    end

    local prev = item_12h.checked_func()
    item_12h.callback()
    assert.are.equal("TimeFormatChanged", broadcasted)
    assert.are_not_equal(prev, item_12h.checked_func())

    item_12h.callback()
    assert.are.equal(prev, item_12h.checked_func())

    UIManager.broadcastEvent = orig_broadcast
  end)

  it("should handle duration format options and text generation", function()
    local item_duration = time_menu.sub_item_table[2]
    assert.is_not_nil(item_duration)
    assert.is_function(item_duration.text_func)
    assert.is_table(item_duration.sub_item_table)

    local broadcasted
    local orig_broadcast = UIManager.broadcastEvent
    UIManager.broadcastEvent = function(self, ev)
      broadcasted = ev
    end

    -- Sub items: classic, modern, letters
    local sub_items = item_duration.sub_item_table
    assert.are.equal(3, #sub_items)

    -- Classic
    assert.is_string(sub_items[1].text_func())
    sub_items[1].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[1].checked_func())
    assert.is_false(sub_items[2].checked_func())
    assert.is_false(sub_items[3].checked_func())
    assert.is_true(item_duration.text_func():find("Classic") ~= nil)

    -- Modern
    assert.is_string(sub_items[2].text_func())
    sub_items[2].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[2].checked_func())
    assert.is_false(sub_items[1].checked_func())
    assert.is_true(item_duration.text_func():find("Modern") ~= nil)

    -- Letters
    assert.is_string(sub_items[3].text_func())
    sub_items[3].callback()
    assert.are.equal("UpdateFooter", broadcasted)
    assert.is_true(sub_items[3].checked_func())
    assert.is_false(sub_items[2].checked_func())
    assert.is_true(item_duration.text_func():find("Letters") ~= nil)

    UIManager.broadcastEvent = orig_broadcast
  end)

  it("should handle Set time and Set date dialogs when supported", function()
    local orig_set_dt = Device.setDateTime
    Device.setDateTime = function()
      return true
    end

    package.loaded["ui/elements/time_settings_menu_table"] = nil
    local custom_menu = require("ui/elements/time_settings_menu_table")

    local item_time, item_date
    for _, item in ipairs(custom_menu.sub_item_table) do
      if item.text == "Set time" then
        item_time = item
      elseif item.text == "Set date" then
        item_date = item
      end
    end

    assert.is_not_nil(item_time)
    assert.is_not_nil(item_date)

    local shown_widget
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_widget = w
    end

    -- Test Set time callback
    item_time.callback()
    local time_dialog = shown_widget
    assert.is_not_nil(time_dialog)
    assert.is_function(time_dialog.callback)
    time_dialog.callback({ hour = 10, min = 30 })

    -- Test failure case of Set time
    Device.setDateTime = function(self, y, m, d, h, min)
      if h then
        return false
      end
      return true
    end
    time_dialog.callback({ hour = 10, min = 30 })

    -- Test Set date callback
    item_date.callback()
    local date_dialog = shown_widget
    assert.is_not_nil(date_dialog)
    assert.is_function(date_dialog.callback)
    Device.setDateTime = function()
      return true
    end
    date_dialog.callback({ year = 2026, month = 8, day = 24 })

    -- Test failure case of Set date
    Device.setDateTime = function()
      return false
    end
    date_dialog.callback({ year = 2026, month = 8, day = 24 })

    UIManager.show = orig_show
    Device.setDateTime = orig_set_dt
    package.loaded["ui/elements/time_settings_menu_table"] = nil
  end)
end)
