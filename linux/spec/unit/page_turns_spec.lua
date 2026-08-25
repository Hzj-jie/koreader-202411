describe("PageTurns element", function()
  local PageTurns, ReaderUI, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    UIManager = require("ui/uimanager")
    ReaderUI = require("apps/reader/readerui")
    ReaderUI.instance = {
      view = {
        setupTouchZones = function() end,
        inverse_reading_order = false,
        onToggleReadingOrder = function() end,
      },
    }

    PageTurns = require("ui/elements/page_turns")
  end)

  it("should expose PageTurns menu structure and submenu items", function()
    assert.is_table(PageTurns)
    assert.is_table(PageTurns.sub_item_table)
    assert.is_true(#PageTurns.sub_item_table >= 4)
  end)

  it(
    "should handle page turn toggle callbacks and checked functions",
    function()
      local sub_items = PageTurns.sub_item_table

      assert.is_boolean(sub_items[1].checked_func())
      sub_items[1].callback()

      assert.is_boolean(sub_items[2].checked_func())
      sub_items[2].callback()

      assert.is_string(sub_items[3].text_func())
      assert.is_boolean(sub_items[3].enabled_func())
      assert.is_table(sub_items[3].sub_item_table)
    end
  )

  it(
    "should handle tap zone configuration subitems and ratio spinwidget",
    function()
      local tap_sub_items = PageTurns.sub_item_table[3].sub_item_table
      assert.is_table(tap_sub_items)
      assert.is_true(#tap_sub_items >= 4)

      -- Test left_right, top_bottom, bottom_top callbacks
      assert.is_boolean(tap_sub_items[1].checked_func())
      tap_sub_items[1].callback()

      assert.is_boolean(tap_sub_items[2].checked_func())
      tap_sub_items[2].callback()

      assert.is_boolean(tap_sub_items[3].checked_func())
      tap_sub_items[3].callback()

      assert.is_string(tap_sub_items[4].text_func())

      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local dummy_menu = { updateItems = function() end }
      tap_sub_items[4].callback(dummy_menu)
      assert.is_table(shown_widget)
      if shown_widget.callback then
        shown_widget.callback(70)
      end
      UIManager.show = orig_show
    end
  )

  it("should handle inverted reading order toggles and hold dialog", function()
    local sub_items = PageTurns.sub_item_table
    local invert_item = sub_items[4]
    assert.is_table(invert_item)

    G_reader_settings:save("inverse_reading_order", false)
    assert.is_string(invert_item.text_func())
    assert.is_false(invert_item.checked_func())
    invert_item.callback()

    G_reader_settings:save("inverse_reading_order", true)
    assert.is_string(invert_item.text_func())

    local shown_confirm
    local orig_show = UIManager.show
    UIManager.show = function(self, w)
      shown_confirm = w
    end

    local dummy_menu = { updateItems = function() end }
    invert_item.hold_callback(dummy_menu)
    assert.is_table(shown_confirm)
    assert.is_string(shown_confirm.choice1_text_func())
    assert.is_string(shown_confirm.choice2_text_func())
    shown_confirm.choice1_callback()
    shown_confirm.choice2_callback()
    UIManager.show = orig_show
  end)

  it(
    "should handle document-related dialog inversion and swipe animations",
    function()
      local sub_items = PageTurns.sub_item_table
      local mirror_item = sub_items[5]
      if mirror_item then
        assert.is_boolean(mirror_item.checked_func())
        assert.is_boolean(mirror_item.enabled_func())
        mirror_item.callback()
      end

      local anim_item = sub_items[6]
      if anim_item then
        assert.is_boolean(anim_item.checked_func())
        anim_item.callback()
      end
    end
  )
end)
