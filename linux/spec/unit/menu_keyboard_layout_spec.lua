describe("Menu Keyboard Layout element", function()
  local menu_keyboard_layout
  local VirtualKeyboard
  local UIManager
  local Device

  setup(function()
    require("commonrequire")
    menu_keyboard_layout = require("ui/elements/menu_keyboard_layout")
    VirtualKeyboard = require("ui/widget/virtualkeyboard")
    UIManager = require("ui/uimanager")
    Device = require("device")
  end)

  before_each(function()
    G_reader_settings:save("keyboard_layouts", { "en" })
    G_reader_settings:save("keyboard_layout_default", "en")
    G_reader_settings:save("keyboard_remember_layout", nil)
    G_reader_settings:save("keyboard_swipes_enabled", nil)
    G_reader_settings:save("keyboard_key_font_size", nil)
    G_reader_settings:save("keyboard_key_bold", nil)
    G_reader_settings:save("keyboard_key_border", nil)
    G_reader_settings:save("keyboard_key_compact", nil)
  end)

  it("should return the sub item table with expected structure", function()
    assert.is_table(menu_keyboard_layout)

    if Device:isTouchDevice() then
      assert.are.equal(5, #menu_keyboard_layout)
    else
      assert.are.equal(4, #menu_keyboard_layout)
    end
  end)

  it("should correctly handle keyboard layouts summary and submenu", function()
    G_reader_settings:save("keyboard_layouts", { "en" })

    local summary_item = menu_keyboard_layout[1]

    -- Test summary text_func
    local text = summary_item.text_func()
    assert.is_string(text)
    assert.is_not_nil(text:find("Keyboard layouts"))

    -- Test fallback when keyboard_layouts is empty
    G_reader_settings:save("keyboard_layouts", {})
    text = summary_item.text_func()
    assert.is_string(text)

    -- Test truncated text when summary width exceeds screen width limit
    G_reader_settings:save("keyboard_layouts", { "en", "fr" })
    local Screen = Device.screen
    local old_width = Screen.getWidth
    Screen.getWidth = function()
      return 10
    end

    text = summary_item.text_func()
    assert.is_string(text)
    assert.is_not_nil(text:find("%("))

    Screen.getWidth = old_width

    -- Test genKeyboardLayoutsSubmenu
    local layout_submenu = summary_item.sub_item_table_func()
    assert.is_table(layout_submenu)
    assert.is_true(#layout_submenu > 0)

    -- Find item for 'en' specifically
    local en_item
    for _, item in ipairs(layout_submenu) do
      local item_text = item.text_func()
      if item_text:find("English") then
        en_item = item
        break
      end
    end
    assert.is_not_nil(en_item)

    -- Test star indicator when 'en' is default layout
    G_reader_settings:save("keyboard_layout_default", "en")
    assert.is_not_nil(en_item.text_func():find("★", 1, true))

    G_reader_settings:save("keyboard_layout_default", "fr")
    assert.is_nil(en_item.text_func():find("★", 1, true))

    -- Test checked_func
    G_reader_settings:save("keyboard_layouts", { "en" })
    assert.is_truthy(en_item.checked_func())

    G_reader_settings:save("keyboard_layouts", { "fr" })
    assert.is_false(en_item.checked_func())

    -- Test callback deselecting an active layout
    G_reader_settings:save("keyboard_layouts", { "en", "fr" })
    en_item.callback()
    local updated_layouts = G_reader_settings:readTableRef("keyboard_layouts")
    assert.are.equal(1, #updated_layouts)
    assert.are.equal("fr", updated_layouts[1])

    -- Test callback selecting a new layout (< 4 active)
    en_item.callback()
    updated_layouts = G_reader_settings:readTableRef("keyboard_layouts")
    assert.are.equal(2, #updated_layouts)

    -- Test callback selecting a layout when limit (4) is reached
    G_reader_settings:save("keyboard_layouts", { "fr", "de", "es", "ru" })
    local ui_show_called = false
    local old_show = UIManager.show
    UIManager.show = function(self, widget)
      ui_show_called = true
    end

    en_item.callback()
    assert.is_true(ui_show_called)
    updated_layouts = G_reader_settings:readTableRef("keyboard_layouts")
    assert.are.equal(4, #updated_layouts)

    UIManager.show = old_show

    -- Test hold_callback
    local update_items_called = false
    local mock_menu = {
      updateItems = function()
        update_items_called = true
      end,
    }
    en_item.hold_callback(mock_menu)
    assert.are.equal("en", G_reader_settings:read("keyboard_layout_default"))
    assert.is_true(update_items_called)
  end)

  it("should handle layout-specific keyboard settings submenu", function()
    local specific_item = menu_keyboard_layout[2]

    -- Case A: No active layouts have layout-specific submenus
    local old_lang_has_submenu = VirtualKeyboard.lang_has_submenu
    VirtualKeyboard.lang_has_submenu = {}
    G_reader_settings:save("keyboard_layouts", { "en" })

    local submenu = specific_item.sub_item_table_func()
    assert.is_table(submenu)
    assert.are.equal(1, #submenu)
    assert.is_nil(submenu[1].sub_item_table_func)
    assert.is_not_nil(submenu[1].text:find("Not available"))

    -- Case B: Active layout has submenu with genMenuItems
    local real_en_keyboard = require("ui/data/keyboardlayouts/en_keyboard")
    VirtualKeyboard.lang_has_submenu = { en = true }
    real_en_keyboard.genMenuItems = function()
      return { { text = "Test Custom Setting" } }
    end

    submenu = specific_item.sub_item_table_func()
    assert.are.equal(1, #submenu)
    local items = submenu[1].sub_item_table_func()
    assert.are.equal(1, #items)
    assert.are.equal("Test Custom Setting", items[1].text)

    -- Case C: Active layout has submenu without genMenuItems
    real_en_keyboard.genMenuItems = nil
    submenu = specific_item.sub_item_table_func()
    assert.are.equal(1, #submenu)
    items = submenu[1].sub_item_table_func()
    assert.are.equal("Not implemented", items.text)

    VirtualKeyboard.lang_has_submenu = old_lang_has_submenu
  end)

  it("should handle 'Remember last layout' setting", function()
    local remember_item
    for _, item in ipairs(menu_keyboard_layout) do
      if item.text and item.text:find("Remember last layout") then
        remember_item = item
        break
      end
    end
    assert.is_not_nil(remember_item)

    G_reader_settings:save("keyboard_remember_layout", true)
    assert.is_true(remember_item.checked_func())

    G_reader_settings:save("keyboard_remember_layout", false)
    assert.is_false(remember_item.checked_func())

    remember_item.callback()
    assert.is_true(G_reader_settings:nilOrTrue("keyboard_remember_layout"))

    remember_item.callback()
    assert.is_false(G_reader_settings:nilOrTrue("keyboard_remember_layout"))
  end)

  it(
    "should handle 'Swipe to input additional characters' setting on touch device",
    function()
      if not Device:isTouchDevice() then
        return
      end

      local swipe_item
      for _, item in ipairs(menu_keyboard_layout) do
        if item.text and item.text:find("Swipe to input") then
          swipe_item = item
          break
        end
      end
      assert.is_not_nil(swipe_item)

      G_reader_settings:save("keyboard_swipes_enabled", true)
      assert.is_true(swipe_item.checked_func())

      G_reader_settings:save("keyboard_swipes_enabled", false)
      assert.is_false(swipe_item.checked_func())

      swipe_item.callback()
      assert.is_true(G_reader_settings:nilOrTrue("keyboard_swipes_enabled"))

      swipe_item.callback()
      assert.is_false(G_reader_settings:nilOrTrue("keyboard_swipes_enabled"))
    end
  )

  it(
    "should handle 'Keyboard appearance settings' dialog and callbacks",
    function()
      local appearance_item
      for _, item in ipairs(menu_keyboard_layout) do
        if item.text and item.text:find("Keyboard appearance settings") then
          appearance_item = item
          break
        end
      end
      assert.is_not_nil(appearance_item)
      assert.is_true(appearance_item.keep_menu_open)

      local shown_dialog
      local old_show = UIManager.show
      local old_close = UIManager.close
      UIManager.show = function(self, widget)
        shown_dialog = widget
      end

      local closed_widget
      UIManager.close = function(self, widget)
        closed_widget = widget
      end

      local menu_updated = false
      local mock_menu = {
        updateItems = function()
          menu_updated = true
        end,
      }

      appearance_item.callback(mock_menu)
      assert.is_not_nil(shown_dialog)

      -- Find Close and Apply buttons in shown_dialog
      local close_btn
      local apply_btn
      for _, row in ipairs(shown_dialog.buttons) do
        for _, btn in ipairs(row) do
          if btn.id == "close" then
            close_btn = btn
          elseif btn.is_enter_default then
            apply_btn = btn
          end
        end
      end

      assert.is_not_nil(close_btn)
      assert.is_not_nil(apply_btn)

      -- Test Close button callback
      close_btn.callback()
      assert.are.equal(shown_dialog, closed_widget)

      -- Mock input_widget methods to track calls during Apply
      local keyboard_closed = false
      local keyboard_inited = false
      local keyboard_shown = false

      shown_dialog._input_widget = {
        closeKeyboard = function()
          keyboard_closed = true
        end,
        initKeyboard = function()
          keyboard_inited = true
        end,
      }
      shown_dialog.showKeyboard = function()
        keyboard_shown = true
      end

      -- Test Apply button callback with invalid font size (<16)
      local input_text = "10"
      shown_dialog.getInputText = function()
        return input_text
      end

      apply_btn.callback()
      assert.is_false(keyboard_closed)
      assert.is_false(menu_updated)

      -- Test Apply button callback with valid font size (22)
      input_text = "22"
      apply_btn.callback()
      assert.is_true(keyboard_closed)
      assert.is_true(keyboard_inited)
      assert.is_true(keyboard_shown)
      assert.is_true(menu_updated)
      assert.are.equal(22, G_reader_settings:read("keyboard_key_font_size"))

      UIManager.show = old_show
      UIManager.close = old_close
    end
  )
end)
