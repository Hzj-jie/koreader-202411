--[[--
A simple plugin for getting the weather forcast on your KOReader

@module koplugin.Weather
--]]
--

local Dispatcher = require("dispatcher") -- luacheck:ignore
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local ListView = require("ui/widget/listview")
local WeatherApi = require("weatherapi")
local Screen = require("device").screen
local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local Font = require("ui/font")
local Composer = require("composer")
local logger = require("logger")
local ffiutil = require("ffi/util")
local _ = require("gettext")
local T = ffiutil.template

local Weather = WidgetContainer:new({
  name = "weather",
  settings_file = DataStorage:getSettingsDir() .. "/weather.lua",
  settings = nil,
  default_postal_code = "X0A0H0",
  default_api_key = "2eec368fb9a149dd8a4224549212507",
  default_temp_scale = "C",
  default_clock_style = "12",
  composer = nil,
  kv = {},
})

function Weather:init()
  self.ui.menu:registerToMainMenu(self)
end

function Weather:loadSettings()
  if self.settings then
    return
  end
  -- Load the default settings
  self.settings = LuaSettings:open(self.settings_file)
  self.postal_code = self.settings:readSetting("postal_code")
    or self.default_postal_code
  self.api_key = self.settings:readSetting("api_key") or self.default_api_key
  self.temp_scale = self.settings:readSetting("temp_scale")
    or self.default_temp_scale
  self.clock_style = self.settings:readSetting("clock_style")
    or self.default_clock_style
  -- Pollinate the other objects that require settings
  self.composer = Composer:new({
    settings = self,
  })
end

function Weather:clock_12()
  return self.clock_style == "12"
end

function Weather:clock_24()
  return self.clock_style == "24"
end

function Weather:celsius()
  return self.temp_scale == "C"
end

function Weather:fahrenheit()
  return self.temp_scale == "F"
end

--
-- Add Weather to the device's menu
--
function Weather:addToMainMenu(menu_items)
  menu_items.weather = {
    sorting_hint = "tools",
    text = _("Weather"),
    sub_item_table_func = function()
      return self:getSubMenuItems()
    end,
  }
end
--
-- Create and return the list of submenu items
--
-- return @array
--
function Weather:getSubMenuItems()
  self:loadSettings()
  local sub_item_table = {
    {
      text = _("Settings"),
      sub_item_table = {
        {
          text_func = function()
            return T(_("Postal Code (%1)"), self.postal_code)
          end,
          keep_menu_open = true,
          callback = function(touchmenu_instance)
            local postal_code = self.postal_code
            local input
            input = InputDialog:new({
              title = _("Postal Code"),
              input = postal_code,
              input_hint = _("Format: " .. self.default_postal_code),
              input_type = "string",
              description = _(""),
              buttons = {
                {
                  {
                    text = _("Cancel"),
                    callback = function()
                      UIManager:close(input)
                    end,
                  },
                  {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                      self.postal_code = input:getInputValue()
                      UIManager:close(input)
                      touchmenu_instance:updateItems()
                    end,
                  },
                },
              },
            })
            UIManager:show(input)
            input:showKeyboard()
          end,
        },
        {
          text_func = function()
            return T(_("Auth Token (%1)"), self.api_key)
          end,
          keep_menu_open = true,
          callback = function(touchmenu_instance)
            local api_key = self.api_key
            local input
            input = InputDialog:new({
              title = _("Auth token"),
              input = api_key,
              input_type = "string",
              description = _(
                "An auth token can be obtained from WeatherAPI.com. Simply signup for an account and request a token."
              ),
              buttons = {
                {
                  {
                    text = _("Cancel"),
                    callback = function()
                      UIManager:close(input)
                    end,
                  },
                  {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                      self.api_key = input:getInputValue()
                      UIManager:close(input)
                      touchmenu_instance:updateItems()
                    end,
                  },
                },
              },
            })
            UIManager:show(input)
            input:showKeyboard()
          end,
        },
        {
          text_func = function()
            return T(_("Temperature Scale (%1)"), self.temp_scale)
          end,
          sub_item_table = {
            {
              text = _("Celsius"),
              checked_func = function()
                return self:celsius()
              end,
              keep_menu_open = true,
              callback = function()
                self.temp_scale = "C"
              end,
            },
            {
              text = _("Fahrenheit"),
              checked_func = function()
                return self:fahrenheit()
              end,
              keep_menu_open = true,
              callback = function(touchmenu_instance)
                self.temp_scale = "F"
              end,
            },
          },
        },
        {
          text_func = function()
            return T(_("Clock style (%1)"), self.clock_style)
          end,
          sub_item_table = {
            {
              text = _("12 hour clock"),
              checked_func = function()
                return self:clock_12()
              end,
              keep_menu_open = true,
              callback = function()
                self.clock_style = "12"
              end,
            },
            {
              text = _("24 hour clock"),
              checked_func = function()
                return self:clock_24()
              end,
              keep_menu_open = true,
              callback = function(touchmenu_instance)
                self.clock_style = "24"
              end,
            },
          },
        },
      },
    },
    {
      text = _("View weather forecast"),
      keep_menu_open = true,
      callback = function()
        NetworkMgr:runWhenOnline(function()
          -- Init the weather API
          local api = WeatherApi:new({
            api_key = self.api_key,
          })
          -- Fetch the forecast, may return results less than 7 days.
          local result = api:getForecast(7, self.postal_code)
          if result == false then
            return false
          end
          if result.error ~= nil then
            local Screen = require("device").screen
            local sample
            sample = InfoMessage:new({
              text = _("Error: " .. result.error.message),
              height = Screen:scaleBySize(400),
              show_icon = true,
            })
            UIManager:show(sample)
          else
            self:weeklyForecast(result)
          end
        end)
      end,
    },
  }
  return sub_item_table
end
--
--
--
function Weather:weeklyForecast(data)
  self.kv = {}
  local view_content = {}

  local vc_weekly = self.composer:createWeeklyForecast(data, function(day_data)
    self:forecastForDay(day_data)
  end)

  view_content = KeyValuePage.flattenArray(view_content, vc_weekly)

  self.kv = KeyValuePage:new({
    title = T(_("Weekly forecast for %1"), data.location.name),
    return_button = true,
    kv_pairs = view_content,
  })

  UIManager:show(self.kv)
end
--
--
--
function Weather:forecastForDay(data)
  local kv = self.kv or {}
  local view_content = {}

  if kv[0] ~= nil then
    UIManager:close(self.kv)
  end

  local day

  if data.forecast == nil then
    day = os.date("%a", data.date_epoch)
    local vc_forecast = self.composer:createForecastFromDay(data)

    if data.current ~= nil then
      local vc_current = self.composer:createCurrentForecast(data.current)
      view_content = KeyValuePage.flattenArray(view_content, vc_current)
    end
    view_content = KeyValuePage.flattenArray(view_content, vc_forecast)
  else
    day = "Today"
    local vc_current = self.composer:createCurrentForecast(data.current)
    local vc_forecast =
      self.composer:createForecastForDay(data.forecast.forecastday[1])
    local location = data.location.name
    view_content = KeyValuePage.flattenArray(view_content, vc_current)
    view_content = KeyValuePage.flattenArray(view_content, vc_forecast)
  end

  -- Add an hourly forecast button to forecast
  table.insert(view_content, {
    _("Hourly forecast"),
    "Click to view",
    callback = function()
      self:hourlyForecast(data.hour)
    end,
  })
  -- Create the KV page
  self.kv = KeyValuePage:new({
    title = T(_("%1 forecast"), day),
    return_button = true,
    kv_pairs = view_content,
  })
  -- Show it
  UIManager:show(self.kv)
end

function Weather:hourlyForecast(data)
  local kv = self.kv
  UIManager:close(self.kv)

  local hourly_kv_pairs = self.composer:hourlyView(data, function(hour_data)
    self:createForecastForHour(hour_data)
  end)

  self.kv = KeyValuePage:new({
    title = _("Hourly forecast"),
    value_overflow_align = "right",
    kv_pairs = hourly_kv_pairs,
    callback_return = function()
      UIManager:show(kv)
      self.kv = kv
    end,
  })

  UIManager:show(self.kv)
end
--
--
--
function Weather:createForecastForHour(data)
  local kv = self.kv
  UIManager:close(self.kv)

  local forecast_kv_pairs = self.composer:forecastForHour(data)

  local date = os.date("*t", data.time_epoch)
  local hour

  if string.find(self.clock_style, "12") then
    if date.hour <= 12 then
      hour = date.hour .. ":00 AM"
    else
      hour = (date.hour - 12) .. ":00 PM"
    end
  else
    hour = date.hour
  end

  self.kv = KeyValuePage:new({
    title = T(_("Forecast for %1"), hour),
    value_overflow_align = "right",
    kv_pairs = forecast_kv_pairs,
    callback_return = function()
      UIManager:show(kv)
      self.kv = kv
    end,
  })

  UIManager:show(self.kv)
end

function Weather:onFlushSettings()
  if self.settings then
    self.settings:saveSetting("postal_code", self.postal_code)
    self.settings:saveSetting("api_key", self.api_key)
    self.settings:saveSetting("temp_scale", self.temp_scale)
    self.settings:saveSetting("clock_style", self.clock_style)
    self.settings:flush()
  end
end

return Weather
