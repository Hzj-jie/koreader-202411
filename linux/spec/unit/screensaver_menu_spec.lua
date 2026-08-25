describe("Screensaver Menu Spec", function()
  local ScreensaverMenu
  local Screensaver

  setup(function()
    require("commonrequire")
    Screensaver = require("ui/screensaver")
    ScreensaverMenu = require("ui/elements/screensaver_menu")
  end)

  it("should provide valid screensaver menu structure", function()
    assert.is_table(ScreensaverMenu)
    assert.is_true(#ScreensaverMenu >= 2)
    assert.is_table(ScreensaverMenu[1].sub_item_table)
    assert.is_table(ScreensaverMenu[2].sub_item_table)
  end)

  it("should handle wallpaper type selections and callbacks", function()
    local wallpaper_menu = ScreensaverMenu[1].sub_item_table
    for _, item in ipairs(wallpaper_menu) do
      if item.radio then
        if item.enabled_func then
          item.enabled_func()
        end
        item.callback()
        assert.is_true(item.checked_func())
      end
    end
  end)

  it("should handle border fill, rotation, and stretch settings", function()
    local wallpaper_menu = ScreensaverMenu[1].sub_item_table
    local border_item = wallpaper_menu[7]
    assert.is_table(border_item)
    assert.is_boolean(border_item.enabled_func())
    assert.is_table(border_item.sub_item_table)

    for _, fill_item in ipairs(border_item.sub_item_table) do
      if fill_item.radio then
        fill_item.callback()
        assert.is_true(fill_item.checked_func())
      end
    end

    local stretch_item = border_item.sub_item_table[4]
    assert.is_table(stretch_item)
    G_reader_settings:save("screensaver_stretch_images", true)
    G_reader_settings:save("screensaver_stretch_limit_percentage", 20)
    assert.is_string(stretch_item.text_func())
    assert.is_true(stretch_item.checked_func())

    local orig_set_limit = Screensaver.setStretchLimit
    local stretch_called = false
    Screensaver.setStretchLimit = function()
      stretch_called = true
    end
    local dummy_menu = { updateItems = function() end }
    stretch_item.callback(dummy_menu)
    assert.is_true(stretch_called)
    Screensaver.setStretchLimit = orig_set_limit

    local rotate_item = border_item.sub_item_table[5]
    assert.is_table(rotate_item)
    rotate_item.callback(dummy_menu)
    assert.is_boolean(rotate_item.checked_func())
  end)

  it("should handle postpone screen update after wakeup", function()
    local wallpaper_menu = ScreensaverMenu[1].sub_item_table
    local postpone_item = wallpaper_menu[8]
    assert.is_table(postpone_item)
    assert.is_table(postpone_item.sub_item_table)

    for _, item in ipairs(postpone_item.sub_item_table) do
      item.callback()
      assert.is_true(item.checked_func())
    end
  end)

  it("should handle custom images choose file and folder", function()
    local wallpaper_menu = ScreensaverMenu[1].sub_item_table
    local custom_item = wallpaper_menu[9]
    assert.is_table(custom_item)
    assert.is_boolean(custom_item.enabled_func())

    local choose_file_called, choose_folder_called = false, false
    local orig_file = Screensaver.chooseFile
    local orig_folder = Screensaver.chooseFolder
    Screensaver.chooseFile = function()
      choose_file_called = true
    end
    Screensaver.chooseFolder = function()
      choose_folder_called = true
    end

    local choose_file_item = custom_item.sub_item_table[1]
    local choose_folder_item = custom_item.sub_item_table[2]
    assert.is_boolean(choose_file_item.enabled_func())
    assert.is_boolean(choose_folder_item.enabled_func())
    choose_file_item.callback()
    choose_folder_item.callback()
    assert.is_true(choose_file_called)
    assert.is_true(choose_folder_called)

    Screensaver.chooseFile = orig_file
    Screensaver.chooseFolder = orig_folder
  end)

  it("should handle sleep screen message options and positioning", function()
    local msg_menu = ScreensaverMenu[2].sub_item_table
    local show_msg_item = msg_menu[1]
    assert.is_table(show_msg_item)
    show_msg_item.callback()
    assert.is_boolean(show_msg_item.checked_func())

    local edit_msg_item = msg_menu[2]
    assert.is_table(edit_msg_item)
    assert.is_boolean(edit_msg_item.enabled_func())
    local orig_set_msg = Screensaver.setMessage
    local set_msg_called = false
    Screensaver.setMessage = function()
      set_msg_called = true
    end
    edit_msg_item.callback()
    assert.is_true(set_msg_called)
    Screensaver.setMessage = orig_set_msg

    local bg_item = msg_menu[3]
    assert.is_table(bg_item)
    assert.is_boolean(bg_item.enabled_func())
    for _, item in ipairs(bg_item.sub_item_table) do
      item.callback()
      assert.is_true(item.checked_func())
    end

    local pos_item = msg_menu[4]
    assert.is_table(pos_item)
    assert.is_boolean(pos_item.enabled_func())
    for _, item in ipairs(pos_item.sub_item_table) do
      item.callback()
      assert.is_true(item.checked_func())
    end

    local hide_reboot_item = msg_menu[5]
    assert.is_table(hide_reboot_item)
    hide_reboot_item.callback()
    assert.is_boolean(hide_reboot_item.checked_func())
  end)
end)
