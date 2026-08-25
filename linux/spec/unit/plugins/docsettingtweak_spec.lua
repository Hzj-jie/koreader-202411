describe("DocSettingTweak plugin module", function()
  local DocSettingTweak, DataStorage, FFIUtil, UIManager, LuaSettings
  local defaults_path

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    FFIUtil = require("ffi/util")
    UIManager = require("ui/uimanager")
    LuaSettings = require("luasettings")

    defaults_path = FFIUtil.joinPath(DataStorage:getSettingsDir(), "directory_defaults.lua")
    DocSettingTweak = require("plugins/docsettingtweak.koplugin/main")
  end)

  teardown(function()
    os.remove(defaults_path)
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    local f = io.open(defaults_path, "w")
    if f then
      f:write("return {}\n")
      f:close()
    end
  end)

  after_each(function()
    os.remove(defaults_path)
  end)

  it("should initialize DocSettingTweak plugin and create directory_defaults.lua", function()
    local registered = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(self_m, plugin)
          registered = true
        end,
      },
    }

    local inst = DocSettingTweak:new({
      ui = mock_ui,
      path = "plugins/docsettingtweak.koplugin",
    })
    inst:init()

    assert.is_true(registered)
    local f = io.open(defaults_path, "r")
    assert.is_not_nil(f)
    f:close()
  end)

  it("should add main menu item and trigger editDirectoryDefaults", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local inst = DocSettingTweak:new({
      ui = mock_ui,
      path = "plugins/docsettingtweak.koplugin",
    })
    inst:init()

    local menu_items = {}
    inst:addToMainMenu(menu_items)
    assert.is_table(menu_items.doc_setting_tweak)
    assert.is_function(menu_items.doc_setting_tweak.callback)

    local shown_widget
    local orig_show = UIManager.show
    UIManager.show = function(self_uim, w) shown_widget = w end

    menu_items.doc_setting_tweak.callback()
    assert.is_table(shown_widget)
    assert.is_function(shown_widget.reset_callback)
    assert.is_function(shown_widget.save_callback)

    -- Test reset_callback
    assert.is_string(shown_widget.reset_callback())

    -- Test save_callback empty
    local ok, msg = shown_widget.save_callback("")
    assert.is_false(ok)

    -- Test save_callback syntax error
    ok, msg = shown_widget.save_callback("return { invalid syntax @#$")
    assert.is_false(ok)

    -- Test save_callback runtime error
    ok, msg = shown_widget.save_callback("error('runtime error')")
    assert.is_false(ok)

    -- Test save_callback valid table
    local valid_lua = "return { ['/books/fiction'] = { font_size = 32 } }"
    ok, msg = shown_widget.save_callback(valid_lua)
    assert.is_true(ok)

    UIManager.show = orig_show
  end)

  it("should apply directory defaults on new document settings load", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
    }
    local inst = DocSettingTweak:new({
      ui = mock_ui,
      path = "plugins/docsettingtweak.koplugin",
    })
    inst:init()

    -- Write defaults configuration
    local test_dir = DataStorage:getDataDir() .. "/test_folder"
    local defaults_content = string.format("return { ['%s'] = { font_size = 40, font_face = 'Serif' } }", test_dir)
    local f = io.open(defaults_path, "w")
    f:write(defaults_content)
    f:close()
    inst:loadDefaults()

    _G.G_named_settings = {
      home_dir = function() return DataStorage:getDataDir() end,
    }

    -- 1. Document with doc_props (already opened) should not be overridden
    local doc_settings_existing = {
      data = {
        doc_props = { title = "Existing Book" },
        font_size = 20,
      },
    }
    local doc_existing = { file = test_dir .. "/book1.epub" }
    inst:onDocSettingsLoad(doc_settings_existing, doc_existing)
    assert.are.equal(20, doc_settings_existing.data.font_size)

    -- 2. Document without doc_props (newly opened) matching folder
    local doc_settings_new = {
      data = {},
    }
    local doc_new = { file = test_dir .. "/subfolder/book2.epub" }
    inst:onDocSettingsLoad(doc_settings_new, doc_new)
    assert.are.equal(40, doc_settings_new.data.font_size)
    assert.are.equal("Serif", doc_settings_new.data.font_face)
    assert.are.equal(doc_new.file, doc_settings_new.data.doc_path)
  end)
end)
