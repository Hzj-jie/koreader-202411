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

  it("should not create a cycle in TouchMenu QuickSettings bar", function()
    local TouchMenu = require("ui/widget/touchmenu")
    local Event = require("ui/event")
    local Device = require("device")
    local stub = require("luassert.stub")

    -- Stub frontlight capability
    local has_fl_stub = stub(Device, "hasFrontlight").returns(true)
    local has_nl_stub = stub(Device, "hasNaturalLight").returns(true)
    local dummy_powerd = {
      fl_min = 0,
      fl_max = 24,
      fl_warmth_min = 0,
      fl_warmth_max = 10,
      frontlightIntensity = function() return 12 end,
      frontlightWarmth = function() return 5 end,
      toNativeWarmth = function(self, w) return w end,
      setIntensity = function() end,
      setWarmth = function() end,
      getBatterySymbol = function() return "batt" end,
      getCapacity = function() return 80 end,
      isCharged = function() return false end,
      isCharging = function() return false end,
    }
    local get_powerd_stub = stub(Device, "getPowerDevice").returns(dummy_powerd)

    -- Enable QSBar
    SUISettings:set("simpleui_bar_enabled", true)
    local package_path = package.path
    package.path = "plugins/simpleui.koplugin/?.lua;" .. package.path
    local QSBar = require("sui_quicksettings_bar")
    QSBar.install()
    package.path = package_path

    -- Construct TouchMenu with the simpleui panel tab active
    local menu = TouchMenu:new({
      width = 400,
      tab_item_table = {
        {
          icon = "simpleui_settings",
          remember = false,
          _sui_qs_panel = true,
          { text = "Item 1" }
        }
      }
    })

    -- Broadcast an event to trigger broadcastEvent recursion
    local ev = Event:new("SomeBroadcastEvent")
    menu:broadcastEvent(ev)

    -- Revert stubs
    has_fl_stub:revert()
    has_nl_stub:revert()
    get_powerd_stub:revert()
  end)
end)
