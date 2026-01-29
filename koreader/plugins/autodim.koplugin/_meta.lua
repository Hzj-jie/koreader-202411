local _ = require("gettext")
return {
  name = "autodim",
  fullname = _("Automatic dimmer"),
  description = _("This plugin allows dimming the frontlight after a period of inactivity.") .. "\n" .. _(
    -- Need localization.
    "KOReader is in idle mode when the frontlight is dimmed."
  ),
}
