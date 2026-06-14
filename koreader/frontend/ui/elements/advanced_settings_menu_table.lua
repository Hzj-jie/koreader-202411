local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local gettext = require("gettext")

return {
  text = gettext("Advanced settings"),
  callback = function()
    SetDefaults:ConfirmEdit()
  end,
}
