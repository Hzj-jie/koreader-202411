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

  it("queries canonical rotation mode", function()
    mock_fb.forced_rotation = { 0, 1, 2, 3 }
    assert.are.equal(0, mock_fb:getCanonicalRotationMode(0))
    assert.are.equal(1, mock_fb:getCanonicalRotationMode(1))
  end)

  it("validates viewport bounds against upright screen_size", function()
    -- Viewports are validated against upright screen_size (600x800)
    assert.has_no.errors(function()
      mock_fb:setViewport({ x = 0, y = 0, w = 500, h = 700 })
    end)

    -- A viewport exceeding unrotated screen width (700 > 600) raises "bad viewport"
    assert.has_error(function()
      mock_fb:setViewport({ x = 0, y = 0, w = 700, h = 500 })
    end, "fb:setViewport() bad viewport")
  end)
end)
