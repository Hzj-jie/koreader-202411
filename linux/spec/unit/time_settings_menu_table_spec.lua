describe("time_settings_menu_table module", function()
  local time_menu

  setup(function()
    require("commonrequire")
    time_menu = require("ui/elements/time_settings_menu_table")
  end)

  it("should export menu structure with sub items", function()
    assert.is_table(time_menu)
    assert.is_string(time_menu.text)
    assert.is_table(time_menu.sub_item_table)
  end)

  it("should return valid 12-hour clock checked status", function()
    local item_12h = time_menu.sub_item_table[1]
    assert.is_not_nil(item_12h)
    assert.is_function(item_12h.checked_func)
    local is_checked = item_12h.checked_func()
    assert.is_boolean(is_checked)
  end)

  it("should generate text for duration format menu item", function()
    local item_duration = time_menu.sub_item_table[2]
    assert.is_not_nil(item_duration)
    assert.is_function(item_duration.text_func)
    local text = item_duration.text_func()
    assert.is_string(text)
  end)
end)
