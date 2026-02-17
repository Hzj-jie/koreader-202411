local Device = require("device")
local UIManager = require("ui/uimanager")
local gettext = require("gettext")
local Screen = Device.screen
local T = require("ffi/util").template

local items = {}
for i = 0, Screen.wf_level_max do
  local info
  if i == 0 then
    info = gettext("Level 0: high quality, slowest")
  elseif i == Screen.wf_level_max then
    info = T(gettext("Level %1: low quality, fastest"), i)
  else
    info = T(gettext("Level %1"), i)
  end

  table.insert(items, {
    text = info,
    checked_func = function()
      return Screen.wf_level == i
    end,
    callback = function()
      Screen.wf_level = i
      G_reader_settings:save("wf_level", i)
      UIManager:askForRestart()
    end,
  })
end

return {
  text = gettext("Refresh speed/fidelity"),
  sub_item_table = items,
}
