local Generic = require("device/generic/device")
local logger = require("logger")
local util = require("util")

local Device = Generic:extend({
  model = "dummy",
  hasKeyboard = util.no,
  hasKeys = util.no,
  isTouchDevice = util.no,
  needsScreenRefreshAfterResume = util.no,
  hasColorScreen = util.yes,
  hasEinkScreen = util.no,
})

function Device:init()
  self.screen = require("ffi/framebuffer_SDL2_0"):new({
    dummy = true,
    device = self,
    debug = logger.dbg,
  })
  Generic.init(self)
end

return Device
