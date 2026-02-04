local Screensaver = require("ui/screensaver")
local gettext = require("gettext")
local lfs = require("libs/libkoreader-lfs")
local T = require("ffi/util").template

local function hasLastFile()
  local last_file = G_reader_settings:read("lastfile")
  return last_file and lfs.attributes(last_file, "mode") == "file"
end

local function isReaderProgressEnabled()
  return Screensaver.getReaderProgress ~= nil and hasLastFile()
end

local function genMenuItem(text, setting, value, enabled_func, separator)
  return {
    text = text,
    enabled_func = enabled_func,
    checked_func = function()
      return G_reader_settings:read(setting) == value
    end,
    callback = function()
      G_reader_settings:save(setting, value)
    end,
    radio = true,
    separator = separator,
  }
end
return {
  {
    text = gettext("Wallpaper"),
    sub_item_table = {
      genMenuItem(gettext("Show book cover on sleep screen"), "screensaver_type", "cover", hasLastFile),
      genMenuItem(gettext("Show custom image or cover on sleep screen"), "screensaver_type", "document_cover"),
      genMenuItem(gettext("Show random image from folder on sleep screen"), "screensaver_type", "random_image"),
      genMenuItem(
        gettext("Show reading progress on sleep screen"),
        "screensaver_type",
        "readingprogress",
        isReaderProgressEnabled
      ),
      genMenuItem(gettext("Show book status on sleep screen"), "screensaver_type", "bookstatus", hasLastFile),
      genMenuItem(gettext("Leave screen as-is"), "screensaver_type", "disable", nil, true),
      separator = true,
      {
        text = gettext("Border fill, rotation, and fit"),
        enabled_func = function()
          return G_reader_settings:read("screensaver_type") == "cover"
            or G_reader_settings:read("screensaver_type") == "document_cover"
            or G_reader_settings:read("screensaver_type") == "random_image"
        end,
        sub_item_table = {
          genMenuItem(gettext("Black fill"), "screensaver_img_background", "black"),
          genMenuItem(gettext("White fill"), "screensaver_img_background", "white"),
          genMenuItem(gettext("No fill"), "screensaver_img_background", "none", nil, true),
          -- separator
          {
            text_func = function()
              local percentage = G_reader_settings:read("screensaver_stretch_limit_percentage")
              if G_reader_settings:isTrue("screensaver_stretch_images") and percentage then
                return T(gettext("Stretch to fit screen (with limit: %1 %)"), percentage)
              end
              return gettext("Stretch cover to fit screen")
            end,
            checked_func = function()
              return G_reader_settings:isTrue("screensaver_stretch_images")
            end,
            callback = function(touchmenu_instance)
              Screensaver:setStretchLimit(touchmenu_instance)
            end,
          },
          {
            text = gettext("Rotate cover for best fit"),
            checked_func = function()
              return G_reader_settings:isTrue("screensaver_rotate_auto_for_best_fit")
            end,
            callback = function(touchmenu_instance)
              G_reader_settings:flipNilOrFalse("screensaver_rotate_auto_for_best_fit")
              touchmenu_instance:updateItems()
            end,
          },
        },
      },
      {
        text = gettext("Postpone screen update after wake-up"),
        sub_item_table = {
          genMenuItem(gettext("Never"), "screensaver_delay", "disable"),
          genMenuItem(gettext("1 second"), "screensaver_delay", "1"),
          genMenuItem(gettext("3 seconds"), "screensaver_delay", "3"),
          genMenuItem(gettext("5 seconds"), "screensaver_delay", "5"),
          genMenuItem(gettext("Until a tap"), "screensaver_delay", "tap"),
          genMenuItem(gettext("Until 'exit sleep screen' gesture"), "screensaver_delay", "gesture"),
        },
      },
      {
        text = gettext("Custom images"),
        enabled_func = function()
          return G_reader_settings:read("screensaver_type") == "random_image"
            or G_reader_settings:read("screensaver_type") == "document_cover"
        end,
        sub_item_table = {
          {
            text = gettext("Choose image or document cover"),
            enabled_func = function()
              return G_reader_settings:read("screensaver_type") == "document_cover"
            end,
            keep_menu_open = true,
            callback = function()
              Screensaver:chooseFile()
            end,
          },
          {
            text = gettext("Choose random image folder"),
            enabled_func = function()
              return G_reader_settings:read("screensaver_type") == "random_image"
            end,
            keep_menu_open = true,
            callback = function()
              Screensaver:chooseFolder()
            end,
          },
        },
      },
    },
  },
  {
    text = gettext("Sleep screen message"),
    sub_item_table = {
      {
        text = gettext("Add custom message to sleep screen"),
        checked_func = function()
          return G_reader_settings:isTrue("screensaver_show_message")
        end,
        callback = function()
          G_reader_settings:flipNilOrFalse("screensaver_show_message")
        end,
        separator = true,
      },
      {
        text = gettext("Edit sleep screen message"),
        enabled_func = function()
          return G_reader_settings:isTrue("screensaver_show_message")
        end,
        keep_menu_open = true,
        callback = function()
          Screensaver:setMessage()
        end,
      },
      {
        text = gettext("Background fill"),
        help_text = gettext(
          "This option will only become available, if you have selected 'Leave screen as-is' as wallpaper and have 'Sleep screen message' on."
        ),
        enabled_func = function()
          return G_reader_settings:read("screensaver_type") == "disable"
            and G_reader_settings:isTrue("screensaver_show_message")
        end,
        sub_item_table = {
          genMenuItem(gettext("Black fill"), "screensaver_msg_background", "black"),
          genMenuItem(gettext("White fill"), "screensaver_msg_background", "white"),
          genMenuItem(gettext("No fill"), "screensaver_msg_background", "none", nil, true),
        },
      },
      {
        text = gettext("Message position"),
        enabled_func = function()
          return G_reader_settings:isTrue("screensaver_show_message")
        end,
        sub_item_table = {
          genMenuItem(gettext("Top"), "screensaver_message_position", "top"),
          genMenuItem(gettext("Middle"), "screensaver_message_position", "middle"),
          genMenuItem(gettext("Bottom"), "screensaver_message_position", "bottom", nil, true),
        },
      },
      {
        text = gettext("Hide reboot/poweroff message"),
        checked_func = function()
          return G_reader_settings:isTrue("screensaver_hide_fallback_msg")
        end,
        callback = function()
          G_reader_settings:flipNilOrFalse("screensaver_hide_fallback_msg")
        end,
      },
    },
  },
}
