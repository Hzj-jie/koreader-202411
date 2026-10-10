local Blitbuffer
local Framebuffer

describe("ffi/framebuffer module", function()
  local mock_fb

  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
    Framebuffer = require("ffi/framebuffer")
  end)

  before_each(function()
    local bb = Blitbuffer.new(600, 800, Blitbuffer.TYPE_BBRGB32)
    mock_fb = Framebuffer:extend({
      bb = bb,
      getRawSize = function(_)
        return { w = 600, h = 800 }
      end,
    })
    mock_fb:init()
  end)

  after_each(function()
    if mock_fb.full_bb then
      mock_fb.full_bb:free()
    elseif mock_fb.bb then
      mock_fb.bb:free()
    end
  end)

  it("calculates dimensions, area, and window titles", function()
    assert.are.equal(600, mock_fb:getWidth())
    assert.are.equal(800, mock_fb:getHeight())
    assert.are.equal(480000, mock_fb:getArea())

    mock_fb:setWindowTitle("Book Title")
    assert.are.equal("Book Title - KOReader", mock_fb:getWindowTitle())

    mock_fb:setWindowTitle(nil)
    assert.are.equal("KOReader", mock_fb:getWindowTitle())
  end)

  it(
    "safely queries canonical rotation mode when forced_rotation is nil",
    function()
      mock_fb.forced_rotation = nil
      -- In expected behavior, default unforced rotation devices should return hw rotation or nil without throwing
      -- In production line 92, fb:getCanonicalRotationMode iterates ipairs(self.forced_rotation) directly
      local ok, mode = pcall(function()
        return mock_fb:getCanonicalRotationMode(0)
      end)
      assert.is_true(ok)
      assert.are.equal(0, mode)
    end
  )

  it(
    "accepts valid landscape viewports after rotating to landscape mode",
    function()
      -- Rotate 90 degrees to landscape: width becomes 800, height becomes 600
      mock_fb:setRotationMode(1)
      assert.are.equal(800, mock_fb:getWidth())
      assert.are.equal(600, mock_fb:getHeight())

      -- A viewport of 700x500 is completely valid on an 800x600 screen
      -- In production lines 272-284, setViewport validates against unrotated screen_size (600x800)
      -- checking 700 > screen_size.w (600) and throwing "bad viewport"
      local ok, err = pcall(function()
        mock_fb:setViewport({ x = 0, y = 0, w = 700, h = 500 })
      end)
      assert.is_true(ok, tostring(err))
    end
  )
end)
