local gettext = require("gettext")
return {
  name = "backgroundrunner",
  fullname = gettext("Background runner"),
  description = gettext(
    [[Service to other plugins: allows tasks to run regularly in the background.]]
  ),
}
