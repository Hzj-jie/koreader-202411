local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local T = require("ffi/util").template

return {
  {
    text = _("About fully refreshing screens"),
    keep_menu_open = true,
    callback = function()
      UIManager:show(InfoMessage:new({
        -- Need localization
        text = _(
          "Showing a new content on an E-ink screen usually does not fully clear the previous content and leaves some blur. It may be referred as E-ink shadow or ghosting.\nThe blur needs a full refresh to be cleared cleanly. But a full refresh can be slow and trigger a flicker.\nKOReader allows users deciding the frequence of the full refresh, i.e. more full refreshes for better display quality or less full refreshes for responsiveness.\nUsually you do not to adjust this configuration, the balanced setting should be good enough for most of the use cases."
        ),
      }))
    end,
  },
  {
    -- Need localization
    text = _("Never automatically fully refresh screen"),
    -- Need localization
    help_text = _(
      "The full refresh will happen only when showing an image, moving to next chapter or opening another book."
    ),
    checked_func = function()
      return G_named_settings.full_refresh_count() == 0
    end,
    callback = function()
      UIManager:broadcastEvent(Event:new("SetRefreshRate", 0))
    end,
    radio = true,
  },
  {
    -- Need localization
    text = _("Low full refresh rate for better responsiveness"),
    checked_func = function()
      return G_named_settings.full_refresh_count() == 48
    end,
    callback = function()
      UIManager:broadcastEvent(Event:new("SetRefreshRate", 48))
    end,
    radio = true,
  },
  {
    -- Need localization
    text = _("Balance between responsiveness and quality"),
    checked_func = function()
      return G_named_settings.full_refresh_count()
        == G_named_settings.default.full_refresh_count()
    end,
    callback = function()
      UIManager:broadcastEvent(
        Event:new(
          "SetRefreshRate",
          G_named_settings.default.full_refresh_count()
        )
      )
    end,
    radio = true,
  },
  {
    -- Need localization
    text = _("High full refresh rate for better display quality"),
    checked_func = function()
      return G_named_settings.full_refresh_count() == 4
    end,
    callback = function()
      UIManager:broadcastEvent(Event:new("SetRefreshRate", 4))
    end,
    radio = true,
    separator = true,
  },
}
