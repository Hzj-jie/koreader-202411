local gettext = require("gettext")
return {
  name = "autodim",
  fullname = gettext("Automatic dimmer"),
  description = gettext(
    "This plugin allows dimming the frontlight after a period of inactivity."
  )
    .. "\n"
    .. gettext(
      -- Need localization.
      "KOReader is in idle mode when the frontlight is dimmed."
    ),
}
