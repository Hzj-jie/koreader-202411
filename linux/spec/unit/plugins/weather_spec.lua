describe("Weather plugin and WeatherApi", function()
  local Weather, WeatherApi, http

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    http = require("socket.http")
    Weather = require("plugins/weather.koplugin/main")
    WeatherApi = require("plugins/weather.koplugin/weatherapi")
  end)

  describe("Weather Main Plugin", function()
    it("should initialize Weather plugin class", function()
      assert.is_table(Weather)
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
