-- luacheck: ignore 122
local BB
local ffi
local FramebufferEinkfb

describe("ffi/framebuffer_einkfb module", function()
  local einkfb_update
  local orig_C

  setup(function()
    require("commonrequire")
    BB = require("ffi/blitbuffer")
    ffi = require("ffi")
    FramebufferEinkfb = require("ffi/framebuffer_einkfb")
    local _, fn = debug.getupvalue(FramebufferEinkfb.refreshPartialImp, 1)
    einkfb_update = fn
    local _, c = debug.getupvalue(einkfb_update, 2)
    orig_C = c
  end)

  after_each(function()
    debug.setupvalue(einkfb_update, 2, orig_C)
  end)

  it("handles nightmode and invert initialization", function()
    local bb = BB.new(100, 100, BB.TYPE_BBRGB32)
    local mock_fb = FramebufferEinkfb:extend({
      bb = bb,
    })

    assert.is_true(mock_fb:reverseNightmode())
    assert.has_no.errors(function()
      mock_fb:initInvert()
    end)
  end)

  it("dispatches refreshFullImp with fx_update_full", function()
    local captured = {}
    local mock_C = setmetatable({
      ioctl = function(fd, req, arg)
        if req == ffi.C.FBIO_EINK_UPDATE_DISPLAY_AREA then
          local area = ffi.cast("struct update_area_t*", arg)
          captured.which_fx = tonumber(area[0].which_fx)
          return 0
        end
        return orig_C.ioctl(fd, req, arg)
      end,
    }, {
      __index = orig_C,
    })

    debug.setupvalue(einkfb_update, 2, mock_C)

    local bb = BB.new(600, 800, BB.TYPE_BBRGB32)
    local mock_fb = FramebufferEinkfb:extend({
      fd = 10,
      bb = bb,
    })

    mock_fb:refreshFullImp(0, 0, 600, 800)
    assert.are.equal(ffi.C.fx_update_full, captured.which_fx)
  end)

  it(
    "sets update_area_t inclusive coordinate bounds without 1-pixel overflow",
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
          return orig_C.ioctl(fd, req, arg)
        end,
      }, {
        __index = orig_C,
      })

      debug.setupvalue(einkfb_update, 2, mock_C)

      local bb = BB.new(600, 800, BB.TYPE_BBRGB32)
      local mock_fb = FramebufferEinkfb:extend({
        fd = 10,
        bb = bb,
      })

      mock_fb:refreshPartialImp(0, 0, 600, 800)
      assert.are.equal(0, captured.x1)
      assert.are.equal(0, captured.y1)
      -- On a 600x800 e-ink panel, inclusive 0-indexed bounds are [0, 599] and [0, 799].
      -- In production line 16-17, refarea[0].x2 = x + w (600) and y2 = y + h (800),
      -- overflowing the display coordinate bounds by 1 pixel.
      assert.are.equal(599, captured.x2)
      assert.are.equal(799, captured.y2)
    end
  )
end)
