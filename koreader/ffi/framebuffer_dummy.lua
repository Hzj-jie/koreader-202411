local BB = require("ffi/blitbuffer")

local framebuffer = {}

function framebuffer:init()
  self.bb = BB.new(600, 800)
  self.bb:fill(BB.COLOR_WHITE)

  framebuffer.parent.init(self)
end

function framebuffer:resize(w, h) end

function framebuffer:_newBB(w, h)
  local rotation
  local inverse

  if self.bb then
    rotation = self.bb:getRotation()
    inverse = self.bb:getInverse() == 1
    self.bb:free()
  end
  if self.invert_bb then
    self.invert_bb:free()
  end

  self.bb = BB.new(w, h, BB.TYPE_BBRGB32)
  self.invert_bb = BB.new(w, h, BB.TYPE_BBRGB32)

  if rotation then
    self.bb:setRotation(rotation)
  end

  -- reinit inverse mode on resize
  if inverse then
    self.bb:invert()
  end
end

function framebuffer:_render(bb, x, y, w, h) end

function framebuffer:refreshFullImp(x, y, w, h) end

function framebuffer:setWindowTitle(new_title) end

function framebuffer:setWindowIcon(icon) end

function framebuffer:close() end

return require("ffi/framebuffer"):extend(framebuffer)
