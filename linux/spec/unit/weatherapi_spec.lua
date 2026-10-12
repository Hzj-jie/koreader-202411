-- luacheck: ignore 122
local http = require("socket.http")

describe("WeatherApi module", function()
  local WeatherApi

  setup(function()
    require("commonrequire")
    WeatherApi = require("plugins/weather.koplugin/weatherapi")
  end)

  it("should initialize with default api key", function()
    local api = WeatherApi:new()
    assert.is_table(api)
    assert.is_string(api.api_key)
  end)

  it(
    "should construct request URL with postal code and forecast days",
    function()
      local requested_url = nil
      local orig_request = http.request
      http.request = function(req)
        requested_url = req.url
        if req.sink then
          req.sink('{"location": {"name": "Seattle"}}')
        end
        return 1, 200, { ["content-type"] = "application/json" }, "OK"
      end
      finally(function()
        http.request = orig_request
      end)

      local api = WeatherApi:new()
      local res = api:getForecast(3, "98101")
      assert.is_table(res)
      assert.is_not_nil(requested_url)
      assert.is_true(requested_url:find("days=3") ~= nil)
      assert.is_true(requested_url:find("q=98101") ~= nil)
    end
  )

  it("returns decoded error payload on non-200 HTTP response", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink(
          '{"error": {"code": 2008, "message": "API key has been disabled"}}'
        )
      end
      return 1, 401, { ["content-type"] = "application/json" }, "Unauthorized"
    end
    finally(function()
      http.request = orig_request
    end)

    local api = WeatherApi:new()
    local res = api:_makeRequest("http://api.weatherapi.com/v1/forecast.json")
    assert.is_table(res)
    assert.is_table(res.error)
    assert.are.equal("API key has been disabled", res.error.message)
  end)

  it("returns nil when JSON decoding fails instead of error string", function()
    local orig_request = http.request
    http.request = function(req)
      if req.sink then
        req.sink("<html><body>502 Bad Gateway</body></html>")
      end
      return 1, 200, { ["content-type"] = "text/html" }, "OK"
    end
    finally(function()
      http.request = orig_request
    end)

    local api = WeatherApi:new()
    local res = api:_makeRequest("http://api.weatherapi.com/v1/forecast.json")
    assert.is_nil(res)
  end)
end)
