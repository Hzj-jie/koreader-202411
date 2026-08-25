describe("Menu Activate Spec", function()
  local MenuActivate
  local UIManager

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    MenuActivate = require("ui/elements/menu_activate")
  end)

  it("should provide menu activate options", function()
    assert.is_table(MenuActivate)
    assert.is_string(MenuActivate.text)
    assert.is_table(MenuActivate.sub_item_table)
    assert.is_true(#MenuActivate.sub_item_table >= 3)
  end)

  it("should handle tap and swipe activation callbacks", function()
    local reload_asked = false
    local orig_reload = UIManager.askForRestartOrReload
    UIManager.askForRestartOrReload = function()
      reload_asked = true
    end

    local tap_item = MenuActivate.sub_item_table[1]
    local swipe_item = MenuActivate.sub_item_table[2]

    tap_item.callback()
    assert.is_true(reload_asked)
    assert.is_boolean(tap_item.checked_func())

    reload_asked = false
    swipe_item.callback()
    assert.is_true(reload_asked)
    assert.is_boolean(swipe_item.checked_func())

    UIManager.askForRestartOrReload = orig_reload
  end)

  it("should handle auto-show bottom menu toggle", function()
    local bottom_item = MenuActivate.sub_item_table[3]
    assert.is_table(bottom_item)
    bottom_item.callback()
    assert.is_boolean(bottom_item.checked_func())
  end)
end)
