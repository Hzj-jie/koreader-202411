local Device = require("device")

local CreUtil = {
  CRE_HEADER_DEFAULT_SIZE = 20,
}

function CreUtil.font_size(value)
  -- Scale like the document font (Screen:scaleBySize), so header size N matches document size N.
  return Device.screen:scaleBySize(value or CreUtil.CRE_HEADER_DEFAULT_SIZE)
end

return CreUtil
