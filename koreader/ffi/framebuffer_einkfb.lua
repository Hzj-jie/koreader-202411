local BB = require("ffi/blitbuffer")
local ffi = require("ffi")
require("ffi/posix_h")
require("ffi/einkfb_h")
local C = ffi.C

local framebuffer = {}

local function flush_hw_rect(fb, lx, ly, lw, lh, px, py, pw, ph)
  if fb.hw_bb then
    fb.hw_bb:setRotation(fb.bb:getRotation())
    if fb.night_mode then
      fb.hw_bb:blitFrom(fb.bb, lx, ly, lx, ly, lw, lh)
    else
      fb.hw_bb:invertblitFrom(fb.bb, lx, ly, lx, ly, lw, lh)
    end
  else
    fb.bb:blitTo4bpp(
      fb.data,
      fb._finfo.line_length,
      px,
      py,
      pw,
      ph,
      not fb.night_mode
    )
  end
end

local function flush_hw_full(fb)
  flush_hw_rect(
    fb,
    0,
    0,
    fb.bb:getWidth(),
    fb.bb:getHeight(),
    0,
    0,
    fb.bb.w,
    fb.bb.h
  )
end

local function einkfb_update(fb, refreshtype, x, y, w, h)
  local bb = fb.bb
  local lx, ly, lw, lh = bb:getBoundedRect(x, y, w, h)
  local px, py, pw, ph = bb:getPhysicalRect(lx, ly, lw, lh)
  if pw <= 0 or ph <= 0 then
    return
  end

  flush_hw_rect(fb, lx, ly, lw, lh, px, py, pw, ph)

  local refarea = ffi.new("struct update_area_t[1]")

  refarea[0].x1 = px
  refarea[0].y1 = py
  refarea[0].x2 = px + pw
  refarea[0].y2 = py + ph
  refarea[0].buffer = nil
  refarea[0].which_fx = refreshtype

  C.ioctl(fb.fd, C.FBIO_EINK_UPDATE_DISPLAY_AREA, refarea)
end

function framebuffer:reinit()
  framebuffer.parent.reinit(self)
  assert(self.fb_bpp == 4 or self.fb_bpp == 8)
  -- Keep the shadow BB non-inverted (TYPE_BB8) so CBB stays enabled;
  -- einkfb hardware inversion is applied when flushing into the HW fb.
  local hw = self.bb
  self.bb = BB.new(hw.w, hw.h, BB.TYPE_BB8)
  if self.fb_bpp == 4 then
    hw:free()
    self.hw_bb = nil
  else
    self.hw_bb = hw
  end
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
  if self.bb and self.data then
    flush_hw_full(self)
  end
  if self.hw_bb then
    self.hw_bb:free()
    self.hw_bb = nil
  end
  framebuffer.parent.close(self, reinit)
end

return require("ffi/framebuffer_linux"):extend(framebuffer)
