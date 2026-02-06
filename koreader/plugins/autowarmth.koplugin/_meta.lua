local gettext = require("gettext")
return {
  name = "autowarmth",
  fullname = require("device"):hasNaturalLight() and gettext(
    "Auto warmth and night mode"
  ) or gettext("Auto night mode"),
  description = gettext(
    [[This plugin allows to set the frontlight warmth automagically.]]
  ),
}
