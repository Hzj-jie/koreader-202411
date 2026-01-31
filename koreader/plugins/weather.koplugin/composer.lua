local _ = require("gettext")

local Composer = {
  settings = {},
}

function Composer:new(o)
  o = o or {}
  self.__index = self
  setmetatable(o, self)
  return o
end

--
-- Takes data.current
--
-- @returns array
--
function Composer:createCurrentForecast(data)
  local view_content = {}

  local condition = data.condition.text
  local feelslike

  if self.settings:celsius() then
    feelslike = data.feelslike_c .. " °C"
  else
    feelslike = data.feelslike_f .. " °F"
  end

  view_content = {
    {
      "Currently feels like ",
      feelslike,
    },
    {
      "Current condition",
      condition,
    },
    "---",
  }

  return view_content
end
--
-- Takes data.forecast.forecastday
--
function Composer:createForecastFromDay(data)
  local view_content = {}
  -- The values I'm interested in seeing
  local condition = data.day.condition.text
  local avg_temp
  local max_temp
  local min_temp
  local moon_phase = data.astro.moon_phase .. ", " .. data.astro.moon_illumination .. "%"
  local moon_rise = data.astro.moonrise
  local moon_set = data.astro.moonset
  local sunrise = data.astro.sunrise
  local sunset = data.astro.sunset

  if self.settings:celsius() then
    avg_temp = data.day.avgtemp_c .. " °C"
    max_temp = data.day.maxtemp_c .. " °C"
    min_temp = data.day.mintemp_c .. " °C"
  else
    avg_temp = data.day.avgtemp_f .. " °F"
    max_temp = data.day.maxtemp_f .. " °F"
    min_temp = data.day.mintemp_f .. " °F"
  end

  -- Set and order the data
  view_content = {
    {
      "High of",
      max_temp,
    },
    {
      "Low of",
      min_temp,
    },
    {
      "Average temp.",
      avg_temp,
    },
    {
      "Condition",
      condition,
    },
    "---",
    {
      "Moonrise",
      moon_rise,
    },
    {
      "Moonset",
      moon_set,
    },
    {
      "Moon phase",
      moon_phase,
    },
    "---",
    {
      "Sunrise",
      sunrise,
    },
    {
      "Sunset",
      sunset,
    },
    "---",
  }

  return view_content
end
---
---
---
function Composer:hourlyView(data, callback)
  local view_content = {}
  local hourly_forecast = data

  -- I'm starting the view at 7AM, because no reasonable person should be
  -- up before this time... Kidding! I'm starting at 7AM because *most*
  -- reasonable people are not up before this time :P
  for i = 7, 20, 1 do
    local cell
    local time

    if self.settings:celsius() then
      cell = hourly_forecast[i + 1].feelslike_c .. "°C, "
    else
      cell = hourly_forecast[i + 1].feelslike_f .. "°F, "
    end

    if self.settings:clock_12() then
      local meridiem
      local hour = i
      if hour <= 12 then
        meridiem = "AM"
      else
        meridiem = "PM"
        hour = hour - 12
      end
      time = hour .. ":00 " .. meridiem
    else
      time = i .. ":00"
    end

    table.insert(view_content, {
      _(time),
      cell .. hourly_forecast[i + 1].condition.text,
      callback = function()
        callback(hourly_forecast[i + 1])
      end,
    })
  end

  return view_content
end

function Composer:forecastForHour(data)
  local view_content = {}

  local feelslike
  local windchill
  local heatindex
  local dewpoint
  local temp
  local precip
  local wind

  local time = data.time
  local condition = data.condition.text
  local uv = data.uv

  if self.settings:celsius() then
    feelslike = data.feelslike_c .. "°C"
    windchill = data.windchill_c .. "°C"
    heatindex = data.heatindex_c .. "°C"
    dewpoint = data.dewpoint_c .. "°C"
    temp = data.temp_c .. "°C"
    precip = data.precip_mm .. " mm"
    wind = data.wind_kph .. " KPH"
  else
    feelslike = data.feelslike_f .. "°F"
    windchill = data.windchill_f .. "°F"
    heatindex = data.heatindex_f .. "°F"
    dewpoint = data.dewpoint_f .. "°F"
    temp = data.temp_f .. "°F"
    precip = data.precip_in .. " in"
    wind = data.wind_mph .. " MPH"
  end

  view_content = {
    {
      "Time",
      time,
    },
    {
      "Temperature",
      temp,
    },
    {
      "Feels like",
      feelslike,
    },
    {
      "Condition",
      condition,
    },
    "---",
    {
      "Precipitation",
      precip,
    },
    {
      "Wind",
      wind,
    },
    {
      "Dewpoint",
      dewpoint,
    },
    "---",
    {
      "Heat Index",
      heatindex,
    },
    {
      "Wind chill",
      windchill,
    },
    "---",
    {
      "UV",
      uv,
    },
  }

  return view_content
end
--
--
--
function Composer:createWeeklyForecast(data, callback)
  local view_content = {}

  local index = 0

  for _, r in ipairs(data.forecast.forecastday) do
    local date = r.date
    local condition = r.day.condition.text
    local avg_temp = nil
    local max_temp = nil
    local min_temp = nil

    if self.settings:celsius() then
      avg_temp = r.day.avgtemp_c .. "°C"
      max_temp = r.day.maxtemp_c .. "°C"
      min_temp = r.day.mintemp_c .. "°C"
    else
      avg_temp = r.day.avgtemp_f .. "°F"
      max_temp = r.day.maxtemp_f .. "°F"
      min_temp = r.day.mintemp_f .. "°F"
    end

    -- @todo: Figure out why os returns the wrong date!
    -- local day = os.date("%A", r.date_epoch)

    -- Add some extra nibbles to the variable that is
    -- passed back to the callback
    if index == 0 then
      r.current = data.current
    end

    local content = {
      {
        date,
        condition,
      },
      {
        "",
        avg_temp,
      },
      {
        "",
        "High: " .. max_temp .. ", Low: " .. min_temp,
      },
      {
        "",
        "Click for full forecast",
        callback = function()
          -- Prepare callback for hour view
          r.location = data.location
          callback(r)
        end,
      },
      "---",
    }

    local KeyValuePage = require("ui/widget/keyvaluepage")
    view_content = KeyValuePage.flattenArray(view_content, content)

    index = index + 1
  end

  return view_content
end

return Composer
