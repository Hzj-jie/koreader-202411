local gettext = require("gettext")
return {
  name = "hello",
  fullname = gettext("Hello"),
  description = gettext([[This is a debugging plugin.]]),
}
