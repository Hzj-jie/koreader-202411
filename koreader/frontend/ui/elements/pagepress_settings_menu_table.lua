local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local C_ = gettext.pgettext
local T = require("ffi/util").template

-- This affects the topmenu, we want to be able to access it even if !Device:setDateTime()
local menu = {
  -- Need localization
  text = gettext("Page press"),
  help_text = gettext("Configure the up and down buttons on both side of the kindle voyage"),
  sub_item_table = {
    {
      text = gettext("Low pressure"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressPressure() == 0
      end,
      callback = function()
        Device:setPagePressPressure(0)
      end,
    },
    {
      text = gettext("Medium pressure"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressPressure() == 1
      end,
      callback = function()
        Device:setPagePressPressure(1)
      end,
    },
    {
      text = gettext("High pressure"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressPressure() == 2
      end,
      callback = function()
        Device:setPagePressPressure(2)
      end,
      separator = true,
    },
    {
      text = gettext("No feedback"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressFeedback() == 0
      end,
      callback = function()
        Device:setPagePressFeedback(0)
      end,
    },
    {
      text = gettext("Low feedback"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressFeedback() == 1
      end,
      callback = function()
        Device:setPagePressFeedback(1)
      end,
    },
    {
      text = gettext("Medium feedback"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressFeedback() == 2
      end,
      callback = function()
        Device:setPagePressFeedback(2)
      end,
    },
    {
      text = gettext("High feedback"),
      keep_menu_open = true,
      radio = true,
      checked_func = function()
        return Device:pagePressFeedback() == 3
      end,
      callback = function()
        Device:setPagePressFeedback(3)
      end,
    },
  },
}

return menu
