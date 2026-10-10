describe("Weather main plugin module", function()
  local Weather
  local UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Weather = require("plugins/weather.koplugin/main")
    UIManager = require("ui/uimanager")
  end)

  describe("initialization and settings", function()
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

    it(
      "should load settings and verify temperature/clock helper methods",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }

        local tmp_file = os.tmpname()
        local inst = Weather:new({ ui = mock_ui, settings_file = tmp_file })
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

        inst:onFlushSettings()

        local LuaSettings = require("luasettings")
        local saved = LuaSettings:open(tmp_file)
        assert.are.equal("F", saved:read("temp_scale"))
        assert.are.equal("24", saved:read("clock_style"))

        os.remove(tmp_file)
      end
    )
  end)

  describe("menu item callbacks and settings submenus", function()
    it(
      "toggles clock and temperature scale options via menu callbacks",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }

        local tmp_file = os.tmpname()
        local inst = Weather:new({ ui = mock_ui, settings_file = tmp_file })
        inst:loadSettings()

        local menu_items = {}
        inst:addToMainMenu(menu_items)
        local sub_items = menu_items.weather.sub_item_table_func()

        -- Settings submenu is item 1
        local settings_menu = sub_items[1].sub_item_table
        assert.is_table(settings_menu)

        -- Clock style item is index 4 in settings submenu
        local clock_item = settings_menu[4]
        assert.is_table(clock_item.sub_item_table)
        local clock_24_item = clock_item.sub_item_table[2]
        clock_24_item.callback()
        assert.are.equal("24", inst.clock_style)
        assert.is_true(inst:clock_24())

        local clock_12_item = clock_item.sub_item_table[1]
        clock_12_item.callback()
        assert.are.equal("12", inst.clock_style)
        assert.is_true(inst:clock_12())

        os.remove(tmp_file)
      end
    )
  end)

  describe("failing tests exposing production bugs", function()
    it(
      "formats 12h clock noon and midnight properly in hourly forecast (fails: noon 12:00 AM bug)",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }

        local inst = Weather:new({ ui = mock_ui })
        inst:loadSettings()
        inst.clock_style = "12"

        -- Stub forecastForHour to isolate hour title formatting
        inst.composer.forecastForHour = function()
          return {}
        end

        local old_show = UIManager.show
        local old_close = UIManager.close
        UIManager.show = function() end
        UIManager.close = function() end

        -- Epoch for 2026-06-15 12:00:00 (noon):
        local noon_epoch = os.time({
          year = 2026,
          month = 6,
          day = 15,
          hour = 12,
          min = 0,
          sec = 0,
        })

        local hour_data = {
          time_epoch = noon_epoch,
        }

        inst:createForecastForHour(hour_data)

        UIManager.show = old_show
        UIManager.close = old_close

        assert.is_table(inst.kv)
        -- Production bug in weather main.lua lines 358-362:
        -- if date.hour <= 12 then hour = date.hour .. ":00 AM" else ...
        -- When date.hour is 12 (noon), it formats as "12:00 AM" instead of "12:00 PM"!
        assert.is_truthy(
          inst.kv.title:find("12:00 PM"),
          "noon should be formatted as 12:00 PM, got: "
            .. tostring(inst.kv.title)
        )
      end
    )

    it(
      "closes previous KeyValuePage before opening forecastForDay (fails: kv[0] check)",
      function()
        local mock_ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        }
        local inst = Weather:new({ ui = mock_ui })
        inst:loadSettings()

        -- Stub composer methods to isolate KV closing logic
        inst.composer.createForecastFromDay = function()
          return {}
        end
        inst.composer.createCurrentForecast = function()
          return {}
        end

        local old_kv = {
          title = "Active Weekly Forecast View",
        }
        inst.kv = old_kv

        local closed_widget
        local old_close = UIManager.close
        local old_show = UIManager.show
        UIManager.close = function(_, widget)
          closed_widget = widget
        end
        UIManager.show = function() end

        local day_data = {
          location = { name = "City", localtime_epoch = 1715774400 },
          current = { temp_c = 20, condition = { text = "Sunny" } },
        }

        inst:forecastForDay(day_data)

        UIManager.close = old_close
        UIManager.show = old_show

        -- Production bug in weather main.lua line 283:
        -- Checks `if kv[0] ~= nil then UIManager:close(self.kv) end`.
        -- Since Lua widgets are 1-indexed tables, kv[0] is always nil,
        -- so UIManager:close is never called on the previously active self.kv!
        assert.are.equal(old_kv, closed_widget)
      end
    )
  end)
end)
