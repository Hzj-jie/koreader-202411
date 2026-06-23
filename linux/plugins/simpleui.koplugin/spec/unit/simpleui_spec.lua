describe("SimpleUI config logic unit tests", function()
  local Config
  local SUISettings

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    -- Patch LuaSettings for compatibility
    local LuaSettings = require("luasettings")
    LuaSettings.readSetting = LuaSettings.read
    LuaSettings.saveSetting = LuaSettings.save
    LuaSettings.delSetting = LuaSettings.delete
    if G_reader_settings then
      local mt = getmetatable(G_reader_settings)
      if mt then
        mt.readSetting = mt.read
        mt.saveSetting = mt.save
        mt.delSetting = mt.delete
      end
    end

    -- Load SUISettings and Config
    local package_path = package.path
    package.path = "plugins/simpleui.koplugin/?.lua;" .. package.path
    SUISettings = require("sui_store")
    Config = require("sui_config")
    package.path = package_path
  end)

  teardown(function()
    package.unloadAll()
  end)

  it("should have correct constants", function()
    assert.are.equal(5, Config.DEFAULT_NUM_TABS)
    assert.are.equal(6, Config.MAX_TABS)
    assert.is_not_nil(Config.ICON.library)
  end)

  it("should apply first run defaults and retrieve topbar config", function()
    -- Clear settings first
    SUISettings:del("simpleui_bar_enabled")
    SUISettings:del("simpleui_bar_tabs")
    SUISettings:del("simpleui_topbar_config")

    -- Run defaults
    Config.applyFirstRunDefaults()

    -- Verify defaults set
    assert.True(SUISettings:get("simpleui_bar_enabled"))
    local tabs = SUISettings:readTable("simpleui_bar_tabs")
    assert.are.equal(5, #tabs)
    assert.are.equal("home", tabs[1])
    assert.are.equal("power", tabs[5])

    -- Get topbar config
    local tb_cfg = Config.getTopbarConfig()
    assert.is_not_nil(tb_cfg)
    assert.are.equal("left", tb_cfg.side.clock)
    assert.are.equal("right", tb_cfg.side.wifi)
    assert.are.equal("clock", tb_cfg.order_left[1])
  end)
end)
