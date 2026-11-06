local gettext = require("gettext")
return {
  name = "autodim",
  fullname = gettext("Automatic dimmer"),
  description = gettext(
    "Automatically dims the frontlight after a period of inactivity.\n\nKOReader enters idle mode after the dimmer's idle time, or after 5 minutes when the dimmer is disabled."
  ),
}
