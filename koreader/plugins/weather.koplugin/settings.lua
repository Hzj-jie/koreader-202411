local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")

function Settings:createAuthDialog(value, default_value, callback)
  local postal_code = self.postal_code
  local input

  input = InputDialog:new({
    title = gettext("Auth token"),
    input = value,
    input_type = "string",
    description = gettext("WeatherAPI auth token"),
    buttons = {
      {
        {
          text = gettext("Cancel"),
          callback = function()
            UIManager:close(input)
          end,
        },
        {
          text = gettext("Save"),
          is_enter_default = true,
          callback = callback(input),
        },
      },
    },
  })

  return input
end
