describe("SlidePuzzle Settings module", function()
  local Settings, LuaSettings, UIManager, I18n, ffiUtil

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Settings = require("plugins/slidepuzzle.koplugin/slidepuzzle_settings")
    LuaSettings = require("luasettings")
    UIManager = require("ui/uimanager")
    I18n = require("plugins/slidepuzzle.koplugin/slidepuzzle_i18n")
    ffiUtil = require("ffi/util")
  end)

  local tmp_settings_file

  after_each(function()
    if tmp_settings_file then
      os.remove(tmp_settings_file)
      tmp_settings_file = nil
    end
  end)

  local function get_temp_file()
    return string.format(
      "/tmp/slidepuzzle_settings_test_%d_%d.lua",
      ffiUtil.getpid(),
      os.time()
    )
  end

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
    tmp_settings_file = get_temp_file()
    local mock_settings = LuaSettings:open(tmp_settings_file)
    local mock_plugin = {
      settings = mock_settings,
    }

    local font = Settings.getFont(mock_plugin)
    assert.is_table(font)
    assert.are.equal("default", font.id)

    local font_size = Settings.getFontSize(mock_plugin)
    assert.are.equal(Settings.AUTO_FONT_SIZE, font_size)
  end)

  it("should handle font selection and settings callback", function()
    tmp_settings_file = get_temp_file()
    local mock_settings = LuaSettings:open(tmp_settings_file)
    local settings_changed = false
    local mock_plugin = {
      settings = mock_settings,
      onSettingsChanged = function()
        settings_changed = true
      end,
    }

    local menu_items = Settings.buildSubMenu(mock_plugin)
    local font_item = menu_items[2]
    assert.is_table(font_item.sub_item_table)

    -- Switch to Sans font
    local sans_sub_item = nil
    for _, item in ipairs(font_item.sub_item_table) do
      if item.text_func():find("Sans %(Noto%)") then
        sans_sub_item = item
        break
      end
    end
    assert.is_not_nil(sans_sub_item)
    assert.is_false(sans_sub_item.checked_func())

    sans_sub_item.callback()
    assert.is_true(settings_changed)
    assert.are.equal("sans", mock_settings:read("font_id"))
    assert.are.equal("sans", Settings.getFont(mock_plugin).id)
    assert.is_true(sans_sub_item.checked_func())
  end)

  it("should configure font size via SpinWidget dialog", function()
    tmp_settings_file = get_temp_file()
    local mock_settings = LuaSettings:open(tmp_settings_file)
    local settings_changed = false
    local mock_plugin = {
      settings = mock_settings,
      active_size = 3,
      onSettingsChanged = function()
        settings_changed = true
      end,
    }

    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end
    finally(function()
      UIManager.show = orig_show
    end)

    local menu_items = Settings.buildSubMenu(mock_plugin)
    local font_size_item = menu_items[3]

    -- Trigger font size spin widget
    font_size_item.callback()
    assert.is_not_nil(shown_widget)

    -- Test user picking explicit font size
    shown_widget.callback({ value = 40 })
    assert.is_true(settings_changed)
    assert.are.equal(40, Settings.getFontSize(mock_plugin))

    -- Test user picking auto-computed size resets to AUTO_FONT_SIZE sentinel (0)
    local auto_px = Settings.computeAutoFontSize(mock_plugin)
    shown_widget.callback({ value = auto_px })
    assert.are.equal(Settings.AUTO_FONT_SIZE, Settings.getFontSize(mock_plugin))
  end)

  it("should handle language switching in settings menu", function()
    tmp_settings_file = get_temp_file()
    local mock_settings = LuaSettings:open(tmp_settings_file)
    local settings_changed = false
    local mock_plugin = {
      settings = mock_settings,
      onSettingsChanged = function()
        settings_changed = true
      end,
    }

    local orig_lang = I18n.getChoice()
    finally(function()
      I18n.setActive(orig_lang)
    end)

    local menu_items = Settings.buildSubMenu(mock_plugin)
    local lang_item = menu_items[4]
    assert.is_table(lang_item.sub_item_table)

    -- Find German (Deutsch) language option
    local de_sub_item = nil
    for _, item in ipairs(lang_item.sub_item_table) do
      if item.text_func() == "Deutsch" then
        de_sub_item = item
        break
      end
    end
    assert.is_not_nil(de_sub_item)
    de_sub_item.callback()

    assert.is_true(settings_changed)
    assert.are.equal("de", mock_settings:read("language"))
    assert.are.equal("de", I18n.getChoice())
  end)

  it("should reset best results through confirmation dialog", function()
    tmp_settings_file = get_temp_file()
    local mock_settings = LuaSettings:open(tmp_settings_file)
    local saved = false
    local mock_plugin = {
      settings = mock_settings,
      stats = { ["3"] = { best_moves = 10, best_time = 25, plays = 5 } },
      _saveAll = function()
        saved = true
      end,
    }

    local shown_widget = nil
    local orig_show = UIManager.show
    UIManager.show = function(self, widget)
      shown_widget = widget
    end
    finally(function()
      UIManager.show = orig_show
    end)

    local menu_items = Settings.buildSubMenu(mock_plugin)
    local reset_item = menu_items[5]
    reset_item.callback()

    assert.is_not_nil(shown_widget)
    assert.is_function(shown_widget.ok_callback)

    -- Confirm reset
    shown_widget.ok_callback()
    assert.is_true(saved)
    assert.are.same({}, mock_plugin.stats)
  end)
end)
