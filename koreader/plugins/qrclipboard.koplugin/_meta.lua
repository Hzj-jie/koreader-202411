local gettext = require("gettext")
return {
  name = "qrclipboard",
  fullname = gettext("QR from clipboard"),
  description = gettext(
    [[This plugin generates a QR code from clipboard content.]]
  ),
}
