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
        text = _("Showing a new content on an E-ink screen usually does not fully clear the previous content and leaves some blur. It may be referred as E-ink shadow or ghosting. The blur needs a full refresh to be cleared cleanly. But a full refresh is slow and can be noticed as a blink.\nKOReader allows users deciding the frequence of the full refresh, i.e. more full refreshes for better display quality or less full refreshes for responsiveness.\nUsually you do not to adjust this configuration, the balanced setting should be good enough for most of the use cases."),
      }))
    end,
  },
  {
  -- Need localization
  text = _("Never fully refresh screen"),
  -- Need localization
  help_text = _()
  },
  {
    -- Need localization
    text = _("Low full refresh rate for better responsiveness"),
  },
  {
    -- Need localization
    text = _("Balance between responsiveness and quality"),
  },
  {
    -- Need localization
    text = _("High full refresh rate for better display quality"),
  },
}
