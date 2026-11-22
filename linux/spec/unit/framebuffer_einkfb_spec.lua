-- luacheck: ignore 122
local BB
local ffi
local FramebufferLinux
local FramebufferEinkfb

local function findUpvalue(fn, target)
  local i = 1
  while true do
    local name, val = debug.getupvalue(fn, i)
    if not name then
      return nil, nil
    end
    if name == target then
      return i, val
    end
    i = i + 1
  end
end

describe("ffi/framebuffer_einkfb module", function()
  local einkfb_update
  local einkfb_C_idx, orig_einkfb_C
  local linux_C_idx, orig_linux_C

  setup(function()
    require("commonrequire")
    BB = require("ffi/blitbuffer")
    ffi = require("ffi")
    FramebufferLinux = require("ffi/framebuffer_linux")
    FramebufferEinkfb = require("ffi/framebuffer_einkfb")
    local _, fn = findUpvalue(FramebufferEinkfb.refreshPartialImp, "einkfb_update")
    einkfb_update = fn
    einkfb_C_idx, orig_einkfb_C = findUpvalue(einkfb_update, "C")
    linux_C_idx, orig_linux_C = findUpvalue(FramebufferLinux.reinit, "C")
    assert.is_not_nil(einkfb_C_idx)
    assert.is_not_nil(linux_C_idx)
  end)

  after_each(function()
    debug.setupvalue(einkfb_update, einkfb_C_idx, orig_einkfb_C)
    debug.setupvalue(FramebufferLinux.reinit, linux_C_idx, orig_linux_C)
  end)

  local function setupFakeFB(opts)
    local xres = opts.xres or 10
    local yres = opts.yres or 6
    local bpp = opts.bpp or 4
    local line_length = opts.line_length or math.floor((xres * bpp + 7) / 8)
    local page_bytes = math.ceil(line_length * yres / 4096) * 4096
    local raw_mem = ffi.new("uint8_t[?]", page_bytes)
    local updates = {}
    local state = {
      closed = false,
      munmapped = false,
      raw_mem = raw_mem,
      updates = updates,
      line_length = line_length,
    }

    local mock_C = setmetatable({
      open = function()
        return 42
      end,
      close = function(fd)
        if fd == 42 then
          state.closed = true
        end
        return 0
      end,
      mmap = function(_, length)
        assert(tonumber(length) == page_bytes)
        return ffi.cast("void *", raw_mem)
      end,
      munmap = function(_, length)
        assert(tonumber(length) == page_bytes)
        state.munmapped = true
        return 0
      end,
      ioctl = function(_, req, arg)
        if req == ffi.C.FBIOGET_FSCREENINFO then
          local finfo = ffi.cast("struct fb_fix_screeninfo *", arg)
          finfo.type = ffi.C.FB_TYPE_PACKED_PIXELS
          finfo.line_length = line_length
          finfo.smem_len = line_length * yres
          return 0
        elseif req == ffi.C.FBIOGET_VSCREENINFO then
          local vinfo = ffi.cast("struct fb_var_screeninfo *", arg)
          vinfo.xres = xres
          vinfo.yres = yres
          vinfo.bits_per_pixel = bpp
          vinfo.rotate = 0
          return 0
        elseif req == ffi.C.FBIO_EINK_UPDATE_DISPLAY_AREA then
          local area = ffi.cast("struct update_area_t *", arg)
          table.insert(updates, {
            x1 = tonumber(area[0].x1),
            y1 = tonumber(area[0].y1),
            x2 = tonumber(area[0].x2),
            y2 = tonumber(area[0].y2),
            which_fx = tonumber(area[0].which_fx),
          })
          return 0
        end
        return 0
      end,
    }, { __index = orig_einkfb_C })

    debug.setupvalue(einkfb_update, einkfb_C_idx, mock_C)
    debug.setupvalue(FramebufferLinux.reinit, linux_C_idx, mock_C)

    local mock_dev = {
      isAlwaysPortrait = function()
        return opts.is_always_portrait == true
      end,
      canHWInvert = function()
        return false
      end,
      canHWDither = function()
        return false
      end,
      canModifyFBInfo = function()
        return false
      end,
      hasEinkScreen = function()
        return true
      end,
      hasBGRFrameBuffer = function()
        return false
      end,
      display_dpi = 167,
    }
    local fb = FramebufferEinkfb:new({ device = mock_dev })
    mock_dev.screen = fb
    return fb, state
  end

  it("dispatches refreshFullImp with fx_update_full", function()
    local captured = {}
    local mock_C = setmetatable({
      ioctl = function(fd, req, arg)
        if req == ffi.C.FBIO_EINK_UPDATE_DISPLAY_AREA then
          local area = ffi.cast("struct update_area_t*", arg)
          captured.which_fx = tonumber(area[0].which_fx)
          return 0
        end
        return orig_einkfb_C.ioctl(fd, req, arg)
      end,
    }, {
      __index = orig_einkfb_C,
    })

    debug.setupvalue(einkfb_update, einkfb_C_idx, mock_C)

    local bb = BB.new(600, 800, BB.TYPE_BB8)
    local hw_bb = BB.new(600, 800, BB.TYPE_BB4)
    local mock_fb = FramebufferEinkfb:extend({
      fd = 10,
      bb = bb,
      hw_bb = hw_bb,
    })

    mock_fb:refreshFullImp(0, 0, 600, 800)
    assert.are.equal(ffi.C.fx_update_full, captured.which_fx)
    hw_bb:free()
    bb:free()
  end)

  it(
    "sets update_area_t coordinate bounds per einkfb.h (x2 = x + w, y2 = y + h)",
    function()
      local captured = {}
      local mock_C = setmetatable({
        ioctl = function(fd, req, arg)
          if req == ffi.C.FBIO_EINK_UPDATE_DISPLAY_AREA then
            local area = ffi.cast("struct update_area_t*", arg)
            captured.x1 = tonumber(area[0].x1)
            captured.y1 = tonumber(area[0].y1)
            captured.x2 = tonumber(area[0].x2)
            captured.y2 = tonumber(area[0].y2)
            captured.which_fx = tonumber(area[0].which_fx)
            return 0
          end
          return orig_einkfb_C.ioctl(fd, req, arg)
        end,
      }, {
        __index = orig_einkfb_C,
      })

      debug.setupvalue(einkfb_update, einkfb_C_idx, mock_C)

      local bb = BB.new(600, 800, BB.TYPE_BB8)
      local hw_bb = BB.new(600, 800, BB.TYPE_BB4)
      local mock_fb = FramebufferEinkfb:extend({
        fd = 10,
        bb = bb,
        hw_bb = hw_bb,
      })

      mock_fb:refreshPartialImp(0, 0, 600, 800)
      assert.are.equal(0, captured.x1)
      assert.are.equal(0, captured.y1)
      -- In einkfb kernel driver (einkfb.h struct update_area_t), (x2 - x1) and (y2 - y1)
      -- represent xres and yres directly, so x2 = x + w (600) and y2 = y + h (800).
      assert.are.equal(600, captured.x2)
      assert.are.equal(800, captured.y2)
      hw_bb:free()
      bb:free()
    end
  )

  it(
    "uses non-inverted BB8 shadow and flushes padded BB4 odd rects in day and night mode",
    function()
      -- line_length = 8 > ceil(10/2) = 5 tests hardware stride padding
      local fb, state = setupFakeFB({ xres = 10, yres = 6, bpp = 4, line_length = 8 })
      assert.are.equal(BB.TYPE_BB8, fb.bb:getType())
      assert.are.equal(0, fb.bb:getInverse())
      if BB:getUseCBB() then
        assert.is_true(fb.bb:canUseCbb())
      end
      -- Initial reinit cleared shadow white -> day HW is inverted (0x00)
      assert.are.equal(0x00, state.raw_mem[0])

      -- Paint at odd x=1, w=3 on y=2 with dark gray (0x00 -> day nibble 0xF)
      fb.bb:paintRect(1, 2, 3, 1, BB.COLOR_BLACK)
      -- Before refresh, HW mmap isn't updated yet
      assert.are.equal(0x00, state.raw_mem[8 * 2 + 0])

      fb:refreshPartial(1, 2, 3, 1)
      assert.are.same({
        { x1 = 1, y1 = 2, x2 = 4, y2 = 3, which_fx = tonumber(ffi.C.fx_update_partial) },
      }, state.updates)
      -- Row 2 nibbles: x=0 (0x0), x=1 (0xF), x=2 (0xF), x=3 (0xF), x=4 (0x0)
      assert.are.equal(0x0F, state.raw_mem[8 * 2 + 0])
      assert.are.equal(0xFF, state.raw_mem[8 * 2 + 1])
      assert.are.equal(0x00, state.raw_mem[8 * 2 + 2])
      -- Row 1 untouched
      assert.are.equal(0x00, state.raw_mem[8 * 1 + 0])

      -- Night mode flips HW polarity immediately without setting shadow inverse
      fb:setNightmode(true)
      assert.are.equal(0, fb.bb:getInverse())
      if BB:getUseCBB() then
        assert.is_true(fb.bb:canUseCbb())
      end
      -- In night mode: black ink (0x00) -> 0x0 nibble, white background (0xFF) -> 0xF nibble
      assert.are.equal(0xF0, state.raw_mem[8 * 2 + 0])
      assert.are.equal(0x00, state.raw_mem[8 * 2 + 1])
      assert.are.equal(0xFF, state.raw_mem[8 * 2 + 2])
      assert.are.equal(0xFF, state.raw_mem[8 * 1 + 0])

      -- clear() fills shadow white and flushes HW to black in night mode, white in day mode
      fb:clear()
      assert.are.equal(0xFF, state.raw_mem[8 * 2 + 0])
      fb:setNightmode(false)
      assert.are.equal(0x00, state.raw_mem[8 * 2 + 0])

      -- Unflushed edits are synced to HW mmap before close/munmap
      fb.bb:paintRect(0, 0, 2, 1, BB.COLOR_BLACK)
      fb:close()
      assert.are.equal(0xFF, state.raw_mem[0])
      assert.is_true(state.munmapped)
      assert.is_true(state.closed)
    end
  )

  it(
    "supports 8bpp hardware (Kindle4) and software rotation cleanly",
    function()
      local fb, state = setupFakeFB({
        xres = 8,
        yres = 12,
        bpp = 8,
        line_length = 12,
        is_always_portrait = true,
      })
      assert.are.equal(BB.TYPE_BB8, fb.bb:getType())
      assert.are.equal(BB.TYPE_BB8, fb.hw_bb:getType())
      fb:setRotationMode(fb.DEVICE_ROTATED_CLOCKWISE)
      assert.are.equal(12, fb:getWidth())
      assert.are.equal(8, fb:getHeight())

      -- DEVICE_ROTATED_CLOCKWISE sets bb rotation 3 (-90 deg -> 270 deg):
      -- rx = y, ry = bb.h - (x + w), rw = h, rh = w
      fb.bb:setPixel(2, 1, BB.Color8(0x22))
      fb:refreshPartial(2, 1, 2, 3)
      -- Physical x = 1, y = 12 - (2 + 2) = 8, w = 3, h = 2
      assert.are.same({
        { x1 = 1, y1 = 8, x2 = 4, y2 = 10, which_fx = tonumber(ffi.C.fx_update_partial) },
      }, state.updates)
      -- (lx=2, ly=1) -> (px = 1, py = 12 - 2 - 1 = 9): day mode inverts 0x22 -> 0xDD
      assert.are.equal(255 - 0x22, state.raw_mem[12 * 9 + 1])

      fb:close()
      assert.is_nil(fb.hw_bb)
      assert.is_nil(fb.bb)
      assert.is_true(state.munmapped)
      assert.is_true(state.closed)
    end
  )
end)
