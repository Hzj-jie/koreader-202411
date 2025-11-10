local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local _ = require("gettext")

return {
  text = _("Advanced settings"),
  callback = function()
    SetDefaults:ConfirmEdit()
  end,
}
