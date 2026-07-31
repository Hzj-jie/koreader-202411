describe("PageTurns element", function()
  local PageTurns, ReaderUI

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

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

  it("should handle page turn toggle callbacks and checked functions", function()
    local sub_items = PageTurns.sub_item_table

    assert.is_boolean(sub_items[1].checked_func())
    sub_items[1].callback()

    assert.is_boolean(sub_items[2].checked_func())
    sub_items[2].callback()

    assert.is_string(sub_items[3].text_func())
    assert.is_boolean(sub_items[3].enabled_func())
    assert.is_table(sub_items[3].sub_item_table)
  end)

  it("should handle tap zone configuration subitems", function()
    local tap_sub_items = PageTurns.sub_item_table[3].sub_item_table
    assert.is_table(tap_sub_items)
    assert.is_true(#tap_sub_items >= 4)

    -- Test left_right, top_bottom, bottom_top callbacks
    assert.is_boolean(tap_sub_items[1].checked_func())
    tap_sub_items[1].callback()

    assert.is_boolean(tap_sub_items[2].checked_func())
    tap_sub_items[2].callback()

    assert.is_string(tap_sub_items[4].text_func())
  end)
end)
