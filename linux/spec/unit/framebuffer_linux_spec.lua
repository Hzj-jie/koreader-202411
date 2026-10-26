-- luacheck: ignore 122
local ffi
local FramebufferLinux

describe("ffi/framebuffer_linux module", function()
  local orig_C
  local dummy_buf

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    FramebufferLinux = require("ffi/framebuffer_linux")
    local _, upval_C = debug.getupvalue(FramebufferLinux.reinit, 1)
    orig_C = upval_C
    dummy_buf = ffi.new("uint8_t[?]", 2097152)
  end)

  after_each(function()
    debug.setupvalue(FramebufferLinux.reinit, 1, orig_C)
  end)

  it(
    "successfully computes stride and dimensions on valid framebuffer info",
    function()
      local mock_C = setmetatable({
        ioctl = function(fd, req, arg)
          if req == ffi.C.FBIOGET_FSCREENINFO then
            local finfo = ffi.cast("struct fb_fix_screeninfo*", arg)
            finfo.type = ffi.C.FB_TYPE_PACKED_PIXELS
            finfo.line_length = 1200
            finfo.smem_len = 2000000
            return 0
          elseif req == ffi.C.FBIOGET_VSCREENINFO then
            local vinfo = ffi.cast("struct fb_var_screeninfo*", arg)
            vinfo.xres = 600
            vinfo.yres = 800
            vinfo.bits_per_pixel = 16
            return 0
          end
          return orig_C.ioctl(fd, req, arg)
        end,
        mmap = function()
          return dummy_buf
        end,
      }, {
        __index = orig_C,
      })

      debug.setupvalue(FramebufferLinux.reinit, 1, mock_C)

      local mock_fb = FramebufferLinux:extend({
        fd = 99,
        _finfo = ffi.new("struct fb_fix_screeninfo"),
        _vinfo = ffi.new("struct fb_var_screeninfo"),
        close = function() end,
        debug = function() end,
        fbinfoOverride = function() end,
      })

      mock_fb:reinit()
      assert.are.equal(1200 * 800, mock_fb.fb_size)
      assert.is_not_nil(mock_fb.bb)
      assert.are.equal(600, mock_fb.bb:getWidth())
      assert.are.equal(800, mock_fb.bb:getHeight())
    end
  )

  it("validates fb_size against smem_len in reinit", function()
    local mock_C = setmetatable({
      ioctl = function(fd, req, arg)
        if req == ffi.C.FBIOGET_FSCREENINFO then
          local finfo = ffi.cast("struct fb_fix_screeninfo*", arg)
          finfo.type = ffi.C.FB_TYPE_PACKED_PIXELS
          finfo.line_length = 1000
          finfo.smem_len = 1000000
          return 0
        elseif req == ffi.C.FBIOGET_VSCREENINFO then
          local vinfo = ffi.cast("struct fb_var_screeninfo*", arg)
          vinfo.xres = 500
          vinfo.yres = 500
          vinfo.bits_per_pixel = 16
          return 0
        end
        return orig_C.ioctl(fd, req, arg)
      end,
      mmap = function()
        return dummy_buf
      end,
    }, {
      __index = orig_C,
    })

    debug.setupvalue(FramebufferLinux.reinit, 1, mock_C)

    local mock_fb = FramebufferLinux:extend({
      fd = 99,
      _finfo = ffi.new("struct fb_fix_screeninfo"),
      _vinfo = ffi.new("struct fb_var_screeninfo"),
      close = function() end,
      debug = function() end,
      fbinfoOverride = function() end,
    })

    mock_fb:reinit()
    assert.are.equal(1000 * 500, mock_fb.fb_size)
  end)
end)
