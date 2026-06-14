local gettext = require("gettext")
return {
  name = "autofrontlight",
  fullname = gettext("Auto frontlight"),
  description = gettext(
    [[Automatically turns the frontlight on and off once brightness in the environment reaches a certain level.]]
  ),
}
