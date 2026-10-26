-- luacheck: ignore 122
local ffi
local FramebufferMxcfb

describe("ffi/framebuffer_mxcfb module", function()
  setup(function()
    require("commonrequire")
    ffi = require("ffi")
    FramebufferMxcfb = require("ffi/framebuffer_mxcfb")
  end)

  it("identifies Kaleido color waveform modes", function()
    local mock_fb = FramebufferMxcfb:extend({
      waveform_color = 10,
      waveform_color_reagl = 11,
    })

    assert.is_true(mock_fb:_isKaleidoWaveFormMode(10))
    assert.is_true(mock_fb:_isKaleidoWaveFormMode(11))
    assert.is_false(mock_fb:_isKaleidoWaveFormMode(12))
  end)

  it("evaluates fullscreen bounds correctly on unrotated screen", function()
    local mock_fb = FramebufferMxcfb:extend({
      getWidth = function()
        return 600
      end,
      getHeight = function()
        return 800
      end,
      getRotationMode = function()
        return 0
      end,
    })

    assert.is_true(mock_fb:_isFullScreen(600, 800))
    assert.is_false(mock_fb:_isFullScreen(300, 400))
  end)

  it(
    "evaluates fullscreen bounds correctly on rotated landscape buffer",
    function()
      local mock_fb = FramebufferMxcfb:extend({
        getWidth = function()
          return 800
        end,
        getHeight = function()
          return 600
        end,
        getRotationMode = function()
          return 1
        end,
      })

      -- _isFullScreen is called after bb:getPhysicalRect(), which converts
      -- logical dimensions (800x600) into physical hardware dimensions (600x800).
      -- In rotation mode 1, band(mode, 1) == 1 swaps physical w and h back to
      -- 800x600 before comparing with getWidth() and getHeight().
      assert.is_true(mock_fb:_isFullScreen(600, 800))
      assert.is_false(mock_fb:_isFullScreen(300, 400))
    end
  )

  it(
    "falls back to AUTO night waveforms on Kobo Condor panels due to upstream fb_bb condition",
    function()
      local mock_device = setmetatable({
        model = "Kobo_condor",
        isKindle = function()
          return false
        end,
        isKobo = function()
          return true
        end,
        isMTK = function()
          return true
        end,
      }, {
        __index = function()
          return function()
            return false
          end
        end,
      })

      local mock_fb = FramebufferMxcfb:extend({
        device = mock_device,
        fb_bpp = 32,
        fb_bb = nil,
        getMxcWaitForBypass = function()
          return false
        end,
        debug = function() end,
      })

      local orig_parent_init = FramebufferMxcfb.parent.init
      FramebufferMxcfb.parent.init = function() end
      mock_fb:init()
      FramebufferMxcfb.parent.init = orig_parent_init

      -- Line 1288 checks `if self.fb_bb ~= 32 then` matching upstream behavior.
      -- Since self.fb_bb is nil, self.waveform_night is set to AUTO.
      assert.are.equal(ffi.C.HWTCON_WAVEFORM_MODE_AUTO, mock_fb.waveform_night)
    end
  )
end)
