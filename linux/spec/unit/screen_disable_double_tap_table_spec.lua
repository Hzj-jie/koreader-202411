describe("screen_disable_double_tap_table module", function()
  local menu_table
  local UIManager

  setup(function()
    require("commonrequire")
    UIManager = require("ui/uimanager")
    menu_table = require("ui/elements/screen_disable_double_tap_table")
  end)

  it("should have correct text and checked_func", function()
    assert.is_equal("Disable double tap", menu_table.text)

    G_reader_settings:save("disable_double_tap", true)
    assert.is_true(menu_table.checked_func())

    G_reader_settings:save("disable_double_tap", false)
    assert.is_false(menu_table.checked_func())
  end)

  it("should toggle setting and prompt for restart on callback", function()
    stub(UIManager, "askForRestartOrReload")

    G_reader_settings:save("disable_double_tap", false)
    menu_table.callback()
    assert.is_true(G_reader_settings:read("disable_double_tap"))
    assert.stub(UIManager.askForRestartOrReload).was_called()

    menu_table.callback()
    assert.is_false(G_reader_settings:read("disable_double_tap"))

    UIManager.askForRestartOrReload:revert()
  end)
end)
