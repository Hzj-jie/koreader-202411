local UIManager = require("ui/uimanager")
local gettext = require("gettext")

return {
  text = gettext("Disable double tap"),
  checked_func = function()
    return G_reader_settings:nilOrTrue("disable_double_tap")
  end,
  callback = function()
    local disabled = G_reader_settings:nilOrTrue("disable_double_tap")
    G_reader_settings:save("disable_double_tap", not disabled)
    UIManager:askForRestart()
  end,
}
