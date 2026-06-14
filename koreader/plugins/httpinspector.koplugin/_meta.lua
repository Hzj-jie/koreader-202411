local gettext = require("gettext")
return {
  name = "httpinspector",
  fullname = gettext("Remotely control KOReader"),
  description = gettext(
    "Allow remotely controlling KOReader via browsers, with advanced "
      .. "features of inspecting KOReader internal state. It poses security "
      .. "risks; only enable this on networks you can trust."
  ),
}
