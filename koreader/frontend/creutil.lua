local Device = require("device")

local CreUtil = {}

function CreUtil.font_size(value)
  -- CRE does not respect the DPI setting in koreader, the font size needs to be
  -- adjusted to match the real size.
  return value * Device.screen:getDPI() / 160
end

return CreUtil
