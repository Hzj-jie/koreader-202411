local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
require("ffi/posix_h")
require("ffi/einkfb_h")
local C = ffi.C

local framebuffer = {}

local function flush_hw_full(fb)
  fb.bb:flushShadow(fb.hw_bb, 0, 0, fb.hw_bb.w, fb.hw_bb.h, not fb.night_mode)
end

local function einkfb_update(fb, refreshtype, x, y, w, h)
  local bb = fb.bb
  x, y, w, h = bb:getBoundedRect(x, y, w, h)
  x, y, w, h = bb:getPhysicalRect(x, y, w, h)
  if w <= 0 or h <= 0 then
    return
  end

  bb:flushShadow(fb.hw_bb, x, y, w, h, not fb.night_mode)

  local refarea = ffi.new("struct update_area_t[1]")

  refarea[0].x1 = x
  refarea[0].y1 = y
  refarea[0].x2 = x + w
  refarea[0].y2 = y + h
  refarea[0].buffer = nil
  refarea[0].which_fx = refreshtype

  C.ioctl(fb.fd, C.FBIO_EINK_UPDATE_DISPLAY_AREA, refarea)
end

function framebuffer:reinit()
  framebuffer.parent.reinit(self)
  assert(
    self.bb:getType() == BB.TYPE_BB4 or self.bb:getType() == BB.TYPE_BB8
  )
  -- Keep the shadow BB non-inverted (TYPE_BB8) so CBB stays enabled;
  -- einkfb hardware inversion is applied when flushing into self.hw_bb.
  self.hw_bb = self.bb
  self.bb = BB.new(self.hw_bb.w, self.hw_bb.h, BB.TYPE_BB8)
  self.bb:fill(BB.COLOR_WHITE)
  flush_hw_full(self)
end

function framebuffer:refreshPartialImp(x, y, w, h)
  einkfb_update(self, C.fx_update_partial, x, y, w, h)
end

function framebuffer:refreshFullImp(x, y, w, h)
  einkfb_update(self, C.fx_update_full, x, y, w, h)
end

function framebuffer:setNightmode(night_mode)
  assert(type(night_mode) == "boolean")
  self.night_mode = night_mode
  flush_hw_full(self)
end

function framebuffer:clear()
  framebuffer.parent.clear(self)
  flush_hw_full(self)
end

function framebuffer:close(reinit)
  if self.hw_bb then
    flush_hw_full(self)
    self.hw_bb:free()
    self.hw_bb = nil
  end
  framebuffer.parent.close(self, reinit)
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
