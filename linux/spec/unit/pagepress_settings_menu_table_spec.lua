describe("Pagepress Settings Menu Table Spec", function()
  local pagepress_menu
  local Device
  local UIManager

  setup(function()
    require("commonrequire")
    Device = require("device")
    UIManager = require("ui/uimanager")
    pagepress_menu = require("ui/elements/pagepress_settings_menu_table")
  end)

  it("should provide valid pagepress menu structure", function()
    assert.is_table(pagepress_menu)
    assert.is_string(pagepress_menu.text)
    assert.is_table(pagepress_menu.sub_item_table)
    assert.is_true(#pagepress_menu.sub_item_table >= 8)
  end)

  it("should handle onKeyPress for try pagepress item", function()
    local try_item = pagepress_menu.sub_item_table[1]
    assert.is_table(try_item)
    assert.is_function(try_item.onKeyPress)

    local dummy_key_match = {
      match = function(self, group)
        return true
      end,
    }
    local dummy_key_non_match = {
      match = function(self, group)
        return false
      end,
    }

    local inverted = false
    local orig_invert = UIManager.invertWidget
    UIManager.invertWidget = function()
      inverted = true
    end

    assert.is_true(try_item.onKeyPress(nil, {}, dummy_key_match))
    assert.is_true(inverted)
    assert.is_false(try_item.onKeyPress(nil, {}, dummy_key_non_match))

    UIManager.invertWidget = orig_invert
  end)

  it("should handle pressure settings callbacks and checked_funcs", function()
    for i = 2, 4 do
      local item = pagepress_menu.sub_item_table[i]
      assert.is_table(item)
      item.callback()
      assert.is_boolean(item.checked_func())
    end
  end)

  it("should handle feedback settings callbacks and checked_funcs", function()
    for i = 5, 8 do
      local item = pagepress_menu.sub_item_table[i]
      assert.is_table(item)
      item.callback()
      assert.is_boolean(item.checked_func())
    end
  end)
end)
