local _ = require("gettext")
local Device = require("device")
local Screen = Device.screen
local T = require("ffi/util").template

local function isAutoDPI()
  return Screen.dpi_override == nil
end

local function dpi()
  return Screen:getDPI()
end

local function custom()
  return G_reader_settings:read("custom_screen_dpi")
end

local function setDPI(dpi_val)
  local UIManager = require("ui/uimanager")
  local text = dpi_val
      and T(
        _("DPI set to %1. This will take effect after restarting."),
        dpi_val
      )
    or _("DPI set to auto. This will take effect after restarting.")
  -- If this is set to nil, reader.lua doesn't call setScreenDPI
  G_reader_settings:saveSetting("screen_dpi", dpi_val)
  -- Passing a nil properly resets to defaults/auto
  Device:setScreenDPI(dpi_val)
  UIManager:askForRestart(text)
end

local function spinWidgetSetDPI(touchmenu_instance)
  local SpinWidget = require("ui/widget/spinwidget")
  local UIManager = require("ui/uimanager")
  local items = SpinWidget:new({
    value = custom() or dpi(),
    value_min = 90,
    value_max = 900,
    value_step = 10,
    value_hold_step = 50,
    ok_text = _("Set DPI"),
    title_text = _("Set custom screen DPI"),
    callback = function(spin)
      G_reader_settings:saveSetting("custom_screen_dpi", spin.value)
      setDPI(spin.value)
      touchmenu_instance:updateItems()
    end,
  })
  UIManager:show(items)
end

local dpi_auto = Screen.device.screen_dpi
local dpi_small = 120
local dpi_medium = 160
local dpi_large = 240
local dpi_xlarge = 320
local dpi_xxlarge = 480
local dpi_xxxlarge = 640

local function predefined_dpi_menu_item(text, dpi_value, lower, upper)
  return {
    text = T(_(text .. " (%1)"), dpi_value),
    checked_func = function()
      if isAutoDPI() then
        return false
      end
      local _dpi = dpi()
      return _dpi and _dpi > lower and _dpi <= upper and _dpi ~= custom()
    end,
    callback = function()
      setDPI(dpi_value)
    end,
    radio = true,
  }
end

return {
  text = _("Screen DPI"),
  sub_item_table = {
    {
      text = dpi_auto and T(_("Auto DPI (%1)"), dpi_auto) or _("Auto DPI"),
      help_text = _(
        "The DPI of your screen is automatically detected so items can be drawn with the right amount of pixels. This will usually display at (roughly) the same size on different devices, while remaining sharp. Increasing the DPI setting will result in larger text and icons, while a lower DPI setting will look smaller on the screen."
      ),
      checked_func = isAutoDPI,
      callback = function()
        setDPI()
      end,
      radio = true,
    },
    predefined_dpi_menu_item("Small", dpi_small, 0, 140),
    predefined_dpi_menu_item("Medium", dpi_medium, 140, 200),
    predefined_dpi_menu_item("Large", dpi_large, 200, 280),
    predefined_dpi_menu_item("Extra Large", dpi_xlarge, 280, 400),
    predefined_dpi_menu_item("Extra-Extra Large", dpi_xxlarge, 400, 560),
    predefined_dpi_menu_item(
      "Extra-Extra-Extra Large",
      dpi_xxxlarge,
      560,
      1000000000
    ),
    {
      text_func = function()
        local custom_dpi = custom() or dpi_auto
        if custom_dpi then
          return T(_("Custom DPI: %1 (hold to set)"), custom() or dpi_auto)
        else
          return _("Custom DPI")
        end
      end,
      checked_func = function()
        if isAutoDPI() then
          return false
        end
        local _dpi, _custom = dpi(), custom()
        return _custom and _dpi == _custom
      end,
      callback = function(touchmenu_instance)
        if custom() then
          setDPI(custom() or dpi_auto)
        else
          spinWidgetSetDPI(touchmenu_instance)
        end
      end,
      hold_callback = function(touchmenu_instance)
        spinWidgetSetDPI(touchmenu_instance)
      end,
      radio = true,
    },
  },
}
