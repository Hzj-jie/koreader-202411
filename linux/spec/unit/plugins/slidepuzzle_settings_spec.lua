describe("SlidePuzzle Settings module", function()
  local Settings, LuaSettings

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Settings = require("plugins/slidepuzzle.koplugin/slidepuzzle_settings")
    LuaSettings = require("luasettings")
  end)

  it("should compute auto font size based on active size", function()
    local mock_plugin = {
      active_size = 3,
    }
    local auto_size = Settings.computeAutoFontSize(mock_plugin)
    assert.is_number(auto_size)
    assert.is_true(auto_size >= Settings.FONT_SIZE_MIN)
    assert.is_true(auto_size <= Settings.FONT_SIZE_MAX)
  end)

  it("should retrieve default font and font size from settings", function()
    local mock_settings = LuaSettings:open(":memory:")
    local mock_plugin = {
      settings = mock_settings,
    }

    local font = Settings.getFont(mock_plugin)
    assert.is_table(font)
    assert.are.equal("default", font.id)

    local font_size = Settings.getFontSize(mock_plugin)
    assert.are.equal(Settings.AUTO_FONT_SIZE, font_size)
  end)

  it("should build settings sub menu with all options and callbacks", function()
    local mock_settings = LuaSettings:open(":memory:")
    local mock_plugin = {
      settings = mock_settings,
      stats = { [3] = { best_moves = 10 } },
      _saveAll = function() end,
      onSettingsChanged = function() end,
    }

    local menu_items = Settings.buildSubMenu(mock_plugin)
    assert.is_table(menu_items)
    assert.is_true(#menu_items >= 4)

    -- Test item text functions
    for _, item in ipairs(menu_items) do
      if item.text_func then
        assert.is_string(item.text_func())
      end
    end

    -- Test toggle setting callback
    menu_items[1].callback()
    assert.is_true(mock_settings:isTrue("always_new_on_open"))
  end)
end)
