-- luacheck: ignore 122
local BB
local FramebufferSDL

describe("ffi/framebuffer_SDL2_0 module", function()
  local orig_SDL

  setup(function()
    require("commonrequire")
    BB = require("ffi/blitbuffer")
    FramebufferSDL = require("ffi/framebuffer_SDL2_0")
    local _, sdl = debug.getupvalue(FramebufferSDL._render, 1)
    orig_SDL = sdl
  end)

  after_each(function()
    debug.setupvalue(FramebufferSDL._render, 1, orig_SDL)
  end)

  it("updates SDL texture with viewport buffer directly", function()
    local captured = {}
    local mock_SDL = setmetatable({
      SDL = {
        SDL_UpdateTexture = function(tex, rect, pixels, pitch)
          captured.rect_w = rect.w
          captured.rect_h = rect.h
          captured.pitch = pitch
        end,
        SDL_RenderClear = function() end,
        SDL_RenderCopy = function() end,
        SDL_RenderPresent = function() end,
      },
    }, {
      __index = orig_SDL,
    })

    debug.setupvalue(FramebufferSDL._render, 1, mock_SDL)

    local bb = BB.new(100, 200, BB.TYPE_BBRGB32)
    bb:rotateAbsolute(90)
    -- Rotated dimensions: width=200, height=100.
    -- Physical unrotated dimensions: pw=100, ph=200.

    local mock_fb = FramebufferSDL:extend({})
    mock_fb:_render(bb, 0, 0, bb:getWidth(), bb:getHeight())

    -- Physical rect passed to SDL is 100x200
    assert.are.equal(100, captured.rect_w)
    assert.are.equal(200, captured.rect_h)
    -- Unrotated buffer pitch for 100 pixels @ 32bpp is 400 bytes
    assert.are.equal(400, captured.pitch)

    bb:free()
  end)
end)
