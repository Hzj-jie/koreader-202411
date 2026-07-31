describe("Weather main plugin module", function()
  local Weather

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Weather = require("plugins/weather.koplugin/main")
  end)

  it("should initialize Weather plugin and register to main menu", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = Weather:new({ ui = mock_ui })
    inst:init()

    local menu_items = {}
    inst:addToMainMenu(menu_items)
    assert.is_table(menu_items.weather)
    assert.is_function(menu_items.weather.sub_item_table_func)

    local sub_items = menu_items.weather.sub_item_table_func()
    assert.is_table(sub_items)
    assert.is_true(#sub_items >= 2)
  end)

  it("should load settings and verify temperature/clock helper methods", function()
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }

    local inst = Weather:new({ ui = mock_ui, settings_file = os.tmpname() })
    inst:loadSettings()

    assert.is_true(inst:celsius())
    assert.is_false(inst:fahrenheit())
    assert.is_true(inst:clock_12())
    assert.is_false(inst:clock_24())

    inst.temp_scale = "F"
    inst.clock_style = "24"

    assert.is_false(inst:celsius())
    assert.is_true(inst:fahrenheit())
    assert.is_false(inst:clock_12())
    assert.is_true(inst:clock_24())

    os.remove(inst.settings_file)
  end)
end)
