-- luacheck: ignore 122
local ffi
local FramebufferIon

describe("ffi/framebuffer_ion module", function()
  local upval_C_idx
  local orig_C

  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    FramebufferIon = require("ffi/framebuffer_ion")
    for i = 1, 20 do
      local name, val = debug.getupvalue(FramebufferIon.init, i)
      if name == "C" then
        upval_C_idx = i
        orig_C = val
        break
      end
    end
  end)

  after_each(function()
    if upval_C_idx and orig_C then
      debug.setupvalue(FramebufferIon.init, upval_C_idx, orig_C)
    end
  end)

  it(
    "validates fb_size against smem_len in init",
    function()
      local mock_C = setmetatable({
        open = function()
          return 99
        end,
        close = function()
          return 0
        end,
        ioctl = function(fd, req, arg)
          if req == ffi.C.FBIOGET_FSCREENINFO then
            local finfo = ffi.cast("struct fb_fix_screeninfo*", arg)
            finfo.type = ffi.C.FB_TYPE_PACKED_PIXELS
            finfo.smem_len = 500000
            return 0
          elseif req == ffi.C.FBIOGET_VSCREENINFO then
            local vinfo = ffi.cast("struct fb_var_screeninfo*", arg)
            vinfo.xres = 600
            vinfo.yres = 600
            vinfo.bits_per_pixel = 8
            vinfo.rotate = 0
            return 0
          end
          return orig_C.ioctl(fd, req, arg)
        end,
      }, {
        __index = orig_C,
      })

      debug.setupvalue(FramebufferIon.init, upval_C_idx, mock_C)

      local mock_fb = setmetatable({
        fb_node = "/dev/fb0",
        ion_node = "/dev/ion",
        disp_node = "/dev/disp",
        fb_bpp = 8,
        boot_rota = 0,
        debug = function() end,
      }, { __index = FramebufferIon })

      local ok = pcall(function()
        mock_fb:init()
      end)
      assert.is_not_nil(mock_fb.fb_size)
      assert.are.equal(360000, mock_fb.fb_size)
    end
  )
end)
