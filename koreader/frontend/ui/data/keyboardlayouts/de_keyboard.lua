-- Start with the english keyboard layout
local de_keyboard =
  require("util").copyRequire("ui/data/keyboardlayouts/en_keyboard")

local keys = de_keyboard.keys

keys[2][6][1], keys[4][2][1] = keys[4][2][1], keys[2][6][1] -- Z <-> Y
keys[2][6][2], keys[4][2][2] = keys[4][2][2], keys[2][6][2] -- z <-> y

return de_keyboard
