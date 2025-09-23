local _ = require("gettext")
return {
  name = "httpinspector",
  -- Need localization.
  fullname = _("Remotely control KOReader"),
  -- Need localization.
  description = _(
    "Allow remotely controlling KOReader via browsers, with advanced "
      .. "features of inspecting KOReader internal state. It poses security "
      .. "risks; only enable this on networks you can trust."
  ),
}
