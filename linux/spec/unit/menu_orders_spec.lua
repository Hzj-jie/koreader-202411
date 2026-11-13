describe("menu_order modules", function()
  setup(function()
    require("commonrequire")
  end)

  it("should merge common_menu_order with custom tables", function()
    local common_menu_order = require("ui/elements/common_menu_order")
    assert.is_function(common_menu_order)

    local merged = common_menu_order({
      custom_category = { "item1", "item2" },
    })
    assert.is_table(merged)
    assert.is_table(merged.custom_category)
    assert.is_table(merged.device)
    assert.is_table(merged.navigation)
    assert.is_table(merged.network)
    assert.is_table(merged.help)
    assert.is_table(merged.exit_menu)
    assert.is_table(merged.setting)
    assert.is_table(merged.screen)
    assert.is_table(merged.taps_and_gestures)
    assert.is_table(merged.tools)
    assert.is_table(merged.search)
    assert.is_table(merged.main)
  end)

  it("should generate filemanager_menu_order structure", function()
    local fm_order = require("ui/elements/filemanager_menu_order")
    assert.is_table(fm_order)
    assert.is_table(fm_order["KOMenu:menu_buttons"])
    assert.is_table(fm_order.filemanager_settings)
    assert.is_table(fm_order.plus_menu)
    assert.is_table(fm_order.search)
  end)

  it("should generate reader_menu_order structure", function()
    local reader_order = require("ui/elements/reader_menu_order")
    assert.is_table(reader_order)
    assert.is_table(reader_order["KOMenu:menu_buttons"])
    assert.is_table(reader_order.navi)
    assert.is_table(reader_order.navi_settings)
    assert.is_table(reader_order.typeset)
    assert.is_table(reader_order.filemanager)
    assert.is_table(reader_order.setting)
    assert.is_table(reader_order.screen)
    assert.is_table(reader_order.document)
    assert.is_table(reader_order.taps_and_gestures)
    assert.is_table(reader_order.search)
    assert.is_table(reader_order.search_settings)
    assert.is_table(reader_order.main)
  end)

  it(
    "should place annotation_sync_plugin in document menu and not in navigation",
    function()
      local util = require("util")
      local common_menu_order = require("ui/elements/common_menu_order")
      local merged = common_menu_order({})
      assert.is_false(
        util.arrayContains(merged.navigation, "annotation_sync_plugin")
      )
      assert.is_truthy(
        util.arrayContains(merged.document, "annotation_sync_plugin")
      )

      local fm_order = require("ui/elements/filemanager_menu_order")
      assert.is_false(
        util.arrayContains(fm_order.navigation, "annotation_sync_plugin")
      )
      assert.is_truthy(
        util.arrayContains(fm_order.document, "annotation_sync_plugin")
      )

      local reader_order = require("ui/elements/reader_menu_order")
      assert.is_false(
        util.arrayContains(reader_order.navigation, "annotation_sync_plugin")
      )
      assert.is_truthy(
        util.arrayContains(reader_order.document, "annotation_sync_plugin")
      )
      assert.is_false(
        util.arrayContains(reader_order.tools, "annotation_sync_plugin")
      )
    end
  )

  it("should place ota_update immediately before help in main menu", function()
    local common_menu_order = require("ui/elements/common_menu_order")
    local fm_order = require("ui/elements/filemanager_menu_order")
    local reader_order = require("ui/elements/reader_menu_order")

    for _, order in ipairs({
      common_menu_order({}).main,
      fm_order.main,
      reader_order.main,
    }) do
      local ota_idx, help_idx
      for i, key in ipairs(order) do
        if key == "ota_update" then
          ota_idx = i
        elseif key == "help" then
          help_idx = i
        end
      end
      assert.is_number(ota_idx)
      assert.is_number(help_idx)
      assert.are.equal(help_idx - 1, ota_idx)
    end
  end)
end)
