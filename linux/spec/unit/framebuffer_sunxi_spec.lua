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

      -- _isFullScreen is called after bb:getPhysicalRect(), which converts
      -- logical dimensions (800x600) into physical hardware dimensions (600x800).
      -- In rotation mode 1, band(mode, 1) == 1 swaps physical w and h back to
      -- 800x600 before comparing with getWidth() and getHeight().
      assert.is_true(mock_fb:_isFullScreen(600, 800))
      assert.is_false(mock_fb:_isFullScreen(300, 400))
    end
  )
end)
