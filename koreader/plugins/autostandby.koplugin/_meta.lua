local gettext = require("gettext")
return {
  name = "autostandby",
  fullname = gettext("Auto Standby"),
  description = gettext(
    [[Put into standby on no input, wake up from standby on UI input]]
  ),
}
