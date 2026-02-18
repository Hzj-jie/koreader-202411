local gettext = require("gettext")
return {
  name = "newsdownloader",
  fullname = gettext("News downloader"),
  description = gettext(
    [[Retrieves RSS and Atom news entries and saves them as HTML files.]]
  ),
}
