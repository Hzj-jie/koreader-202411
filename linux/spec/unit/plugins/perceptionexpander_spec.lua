describe("PerceptionExpander plugin module", function()
  local PerceptionExpander, DataStorage, UIManager, LuaSettings, Blitbuffer, Screen
  local settings_path

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    UIManager = require("ui/uimanager")
    LuaSettings = require("luasettings")
    Blitbuffer = require("ffi/blitbuffer")
    Screen = require("device").screen

    settings_path = DataStorage:getSettingsDir() .. "/perception_expander.lua"
    PerceptionExpander = require("plugins/perceptionexpander.koplugin/main")
  end)

  teardown(function()
    os.remove(settings_path)
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    os.remove(settings_path)
  end)

  after_each(function()
    os.remove(settings_path)
  end)

  it("should initialize PerceptionExpander plugin", function()
    local registered_menu = false
    local registered_view = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function() registered_menu = true end,
      },
      view = {
        registerViewModule = function() registered_view = true end,
      },
      doc_settings = {
        read = function(self_s, key)
          if key == "partial_md5_checksum" then return "12345" end
          return nil
        end,
      },
    }

    local inst = PerceptionExpander:new({ ui = mock_ui })
    inst:init()

    assert.is_table(inst)
    assert.are.equal("perceptionexpander", inst.name)
    assert.is_true(registered_menu)
    assert.is_true(registered_view)
  end)

  it("should create and update UI in portrait and landscape modes", function()
    local inst = PerceptionExpander:new({
      ui = {
        menu = { registerToMainMenu = function() end },
        view = { registerViewModule = function() end },
      },
    })
    inst:init()
    inst.is_enabled = true
    inst:createUI(false)

    assert.is_table(inst[1])
    assert.is_table(inst.left_line)
    assert.is_table(inst.right_line)

    -- Test paintTo
    local bb = Blitbuffer.new(600, 800)
    inst:paintTo(bb, 0, 0)

    -- Test resetLayout
    inst:resetLayout()
    assert.is_table(inst[1])
  end)

  it("should add main menu item, toggle enable, and show settings/about", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      view = { registerViewModule = function() end },
    }
    local inst = PerceptionExpander:new({ ui = mock_ui })
    inst:init()

    local menu_items = {}
    inst:addToMainMenu(menu_items)

    local sub_items = menu_items.speed_reading_module_perception_expander.sub_item_table
    assert.is_table(sub_items)
    assert.are.equal(3, #sub_items)

    -- 1. Toggle Enable
    assert.is_false(sub_items[1].checked_func())
    sub_items[1].callback()
    assert.is_true(inst.is_enabled)

    -- 2. Open Settings dialog
    local shown_widget
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    UIManager.show = function(self_uim, w) shown_widget = w end
    UIManager.close = function() end

    sub_items[2].callback()
    assert.is_table(shown_widget)
    assert.is_table(shown_widget.buttons)

    -- Cancel button
    shown_widget.buttons[1][1].callback()

    -- Apply button
    shown_widget.getFields = function()
      return { "3", "0.15", "5", "50" }
    end
    shown_widget.buttons[1][2].callback()
    assert.are.equal(3, inst.line_thickness)
    assert.are.equal(0.15, inst.margin)
    assert.are.equal(0.5, inst.line_color_intensity)
    assert.are.equal(50, inst.shift_each_pages)

    -- 3. About dialog
    sub_items[3].callback()
    assert.is_table(shown_widget)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it("should handle onPageUpdate and auto-shift margins", function()
    local inst = PerceptionExpander:new({
      ui = {
        menu = { registerToMainMenu = function() end },
        view = { registerViewModule = function() end },
      },
    })
    inst:init()
    inst.is_enabled = true
    inst.shift_each_pages = 2
    inst.page_counter = 0
    inst.margin = 0.1
    inst:createUI(false)

    -- Page 1: increments counter to 1
    inst:onPageUpdate(1)
    assert.are.equal(1, inst.page_counter)

    -- Page 2: increments counter to 2
    inst:onPageUpdate(2)
    assert.are.equal(2, inst.page_counter)

    -- Page 3: reaches threshold (>= 2), shifts margin and resets counter to 0
    inst:onPageUpdate(3)
    assert.are.equal(0, inst.page_counter)
    assert.is_true(inst.margin > 0.1)

    -- Disabled: returns early
    inst.is_enabled = false
    inst:onPageUpdate(4)
  end)
end)
