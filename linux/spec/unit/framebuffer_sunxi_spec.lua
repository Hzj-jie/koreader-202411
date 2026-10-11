local FramebufferSunxi

describe("ffi/framebuffer_sunxi module", function()
  setup(function()
    require("commonrequire")
    FramebufferSunxi = require("ffi/framebuffer_sunxi")
  end)

  it("evaluates fullscreen bounds correctly on unrotated screen", function()
    local mock_fb = FramebufferSunxi:extend({
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
      local mock_fb = FramebufferSunxi:extend({
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

      -- When rotated to landscape (mode 1), getWidth() and getHeight()
      -- already return the rotated viewport dimensions (800 x 600).
      -- In production lines 81-83, _isFullScreen re-swaps w and h when bit 0 of
      -- rotation mode is set, causing w, h = 600, 800 and rejecting 800x600 as fullscreen.
      assert.is_true(mock_fb:_isFullScreen(800, 600))
    end
  )
end)
