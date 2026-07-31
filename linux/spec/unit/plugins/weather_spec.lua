describe("Weather plugin, WeatherApi, and Composer", function()
  local Weather, WeatherApi, Composer, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    Weather = require("plugins/weather.koplugin/main")
    WeatherApi = require("plugins/weather.koplugin/weatherapi")
    Composer = require("plugins/weather.koplugin/composer")
  end)

  describe("Weather Main Plugin", function()
    it("should initialize Weather plugin class and load settings", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      Weather.ui = mock_ui
      Weather:init()
      Weather:loadSettings()

      assert.is_string(Weather.postal_code)
      assert.is_string(Weather.api_key)
      assert.is_boolean(Weather:celsius())
      assert.is_boolean(Weather:clock_12())

      Weather.temp_scale = "F"
      assert.is_true(Weather:fahrenheit())

      Weather.clock_style = "24"
      assert.is_true(Weather:clock_24())

      Weather:onFlushSettings()
    end)

    it("should build main menu item structure", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      Weather.ui = mock_ui

      local menu_items = {}
      Weather:addToMainMenu(menu_items)
      assert.is_table(menu_items.weather)
      assert.is_function(menu_items.weather.sub_item_table_func)

      local items = menu_items.weather.sub_item_table_func()
      assert.is_table(items)
      assert.is_true(#items >= 2)
    end)

    it("should create forecast for hour view without error", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      Weather.ui = mock_ui
      Weather:loadSettings()

      Weather.kv = {
        close = function() end,
        debugStr = function() return "mock" end,
      }
      Weather:createForecastForHour({
        time_epoch = 1715774400,
        temp_c = 20,
        temp_f = 68,
        feelslike_c = 20,
        feelslike_f = 68,
        windchill_c = 20,
        windchill_f = 68,
        heatindex_c = 20,
        heatindex_f = 68,
        dewpoint_c = 10,
        dewpoint_f = 50,
        precip_mm = 0,
        precip_in = 0,
        wind_kph = 5,
        wind_mph = 3,
        chance_of_rain = 0,
        chance_of_snow = 0,
        wind_dir = "N",
        humidity = 50,
        uv = 1,
        condition = { text = "Sunny" },
      })
      assert.is_table(Weather.kv)
    end)
  end)

  describe("Composer Module", function()
    local mock_settings_celsius = {
      celsius = function() return true end,
      clock_12 = function() return true end,
    }
    local mock_settings_fahrenheit = {
      celsius = function() return false end,
      clock_12 = function() return false end,
    }

    it("should create current forecast for C and F scales", function()
      local comp_c = Composer:new({ settings = mock_settings_celsius })
      local comp_f = Composer:new({ settings = mock_settings_fahrenheit })

      local data = {
        condition = { text = "Sunny" },
        feelslike_c = 22,
        feelslike_f = 71.6,
      }

      local res_c = comp_c:createCurrentForecast(data)
      assert.is_table(res_c)

      local res_f = comp_f:createCurrentForecast(data)
      assert.is_table(res_f)
    end)

    it("should create forecast from day for C and F scales", function()
      local comp_c = Composer:new({ settings = mock_settings_celsius })
      local comp_f = Composer:new({ settings = mock_settings_fahrenheit })

      local day_data = {
        day = {
          condition = { text = "Cloudy" },
          avgtemp_c = 18, maxtemp_c = 22, mintemp_c = 14,
          avgtemp_f = 64.4, maxtemp_f = 71.6, mintemp_f = 57.2,
        },
        astro = {
          moon_phase = "Full Moon",
          moon_illumination = "100",
          moonrise = "08:00 PM",
          moonset = "06:00 AM",
          sunrise = "06:30 AM",
          sunset = "07:30 PM",
        },
      }

      assert.is_table(comp_c:createForecastFromDay(day_data))
      assert.is_table(comp_f:createForecastFromDay(day_data))
    end)

    it("should generate hourly view data structure", function()
      local comp_c = Composer:new({ settings = mock_settings_celsius })
      local comp_f = Composer:new({ settings = mock_settings_fahrenheit })

      local hourly = {}
      for i = 1, 24 do
        hourly[i] = {
          feelslike_c = 20,
          feelslike_f = 68,
          condition = { text = "Clear" },
        }
      end

      local callback_called = false
      local view_c = comp_c:hourlyView(hourly, function(item)
        callback_called = true
      end)
      assert.is_table(view_c)
      view_c[1].callback()
      assert.is_true(callback_called)

      local view_f = comp_f:hourlyView(hourly, function() end)
      assert.is_table(view_f)
    end)

    it("should create forecast for specific hour details", function()
      local comp = Composer:new({ settings = mock_settings_celsius })
      local hour_data = {
        time = "12:00",
        condition = { text = "Sunny" },
        uv = 5,
        feelslike_c = 25, windchill_c = 24, heatindex_c = 26, dewpoint_c = 15, temp_c = 25, precip_mm = 0, wind_kph = 10,
      }

      local res = comp:forecastForHour(hour_data)
      assert.is_table(res)
    end)

    it("should create weekly forecast structure", function()
      local comp = Composer:new({ settings = mock_settings_celsius })
      local weekly_data = {
        current = {},
        location = {},
        forecast = {
          forecastday = {
            {
              date = "2024-05-15",
              day = {
                condition = { text = "Sunny" },
                avgtemp_c = 20, maxtemp_c = 25, mintemp_c = 15,
              },
            },
          },
        },
      }

      local clicked = false
      local weekly = comp:createWeeklyForecast(weekly_data, function()
        clicked = true
      end)
      assert.is_table(weekly)
    end)
  end)

  describe("WeatherApi Module", function()
    it("should initialize WeatherApi instance with defaults", function()
      local api = WeatherApi:new()
      assert.is_table(api)
      assert.is_string(api.api_key)
    end)

    it("should handle successful forecast request and JSON parsing", function()
      local old_request = http.request
      http.request = function(req)
        req.sink('{"location":{"name":"London"},"current":{"temp_c":15.0}}')
        return 1, 200, { "content-type" }, "200 OK"
      end

      local api = WeatherApi:new()
      local forecast = api:getForecast(3, "London")
      assert.is_table(forecast)
      assert.is_table(forecast.location)
      assert.are.equal("London", forecast.location.name)

      http.request = old_request
    end)

    it("should handle network failure or missing headers gracefully", function()
      local old_request = http.request
      http.request = function(req)
        return nil
      end

      local api = WeatherApi:new()
      local forecast = api:getForecast(1, "90210")
      assert.is_false(forecast)

      http.request = old_request
    end)

    it("should handle empty response body gracefully", function()
      local old_request = http.request
      http.request = function(req)
        return 1, 200, {}, "200 OK"
      end

      local api = WeatherApi:new()
      local result = api:_makeRequest("http://example.com")
      assert.is_nil(result)

      http.request = old_request
    end)
  end)
end)
