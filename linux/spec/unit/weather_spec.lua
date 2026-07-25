describe("Weather plugin", function()
  local Weather

  setup(function()
    require("commonrequire")
    Weather = require("plugins/weather.koplugin/main")
  end)

  it("should initialize Weather plugin class", function()
    assert.is_table(Weather)
  end)
end)
