local gettext = require("gettext")
return {
  name = "autosuspend",
  fullname = gettext("Auto power save"),
  description = gettext([[Puts the device into standby, suspend or power off after specified periods of inactivity.]]),
}
