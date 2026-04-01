local gettext = require("gettext")
return {
  name = "findhistory",
  -- Need localization
  fullname = gettext("Retrieve reading history"),
  description = gettext(
    [[Searches reading records in the home folder and update the history view.]]
  ),
}
