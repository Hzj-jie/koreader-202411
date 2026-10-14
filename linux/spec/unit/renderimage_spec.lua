describe("RenderImage module", function()
  local RenderImage, Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    RenderImage = require("ui/renderimage")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should handle invalid image data gracefully", function()
    local result = RenderImage:renderImageData(nil, 0)
    assert.is_nil(result)

    result = RenderImage:renderImageData("", 0)
    assert.is_nil(result)
  end)

  it("should return nil when rendering non-existent image file", function()
    local result = RenderImage:renderImageFile("non_existent_image.png")
    assert.is_nil(result)
  end)

  it("should handle corrupted image header gracefully", function()
    local corrupted_data = "CORRUPTED_HEADER_DATA_12345"
    local result = RenderImage:renderImageData(corrupted_data, #corrupted_data)
    assert.is_nil(result)
  end)

  it("should render a checkerboard blitbuffer fallback", function()
    local bb = RenderImage:renderCheckerboard(100, 100)
    assert.is_not_nil(bb)
    assert.are.equal(100, bb:getWidth())
    assert.are.equal(100, bb:getHeight())
    bb:free()
  end)

  it("should scale blitbuffer when dimensions differ", function()
    local orig_bb = Blitbuffer.new(50, 50)
    local same_bb = RenderImage:scaleBlitBuffer(orig_bb, 50, 50)
    assert.are.equal(orig_bb, same_bb)

    local scaled_bb = RenderImage:scaleBlitBuffer(orig_bb, 100, 100)
    assert.is_not_nil(scaled_bb)
    assert.are.equal(100, scaled_bb:getWidth())
    assert.are.equal(100, scaled_bb:getHeight())
    scaled_bb:free()
  end)

  it("should attempt rendering SVG with NanoSVG or MuPDF fallback", function()
    local tmp_svg = os.tmpname()
    local f = io.open(tmp_svg, "w")
    f:write('<svg width="10" height="10"><rect width="10" height="10"/></svg>')
    f:close()

    local bb = RenderImage:renderSVGImageFile(tmp_svg, 20, 20)
    if bb then
      bb:free()
    end

    os.remove(tmp_svg)
  end)

  it("should handle WebP rendering fallback gracefully", function()
    if type(RenderImage.renderWebpImageFile) == "function" then
      local result = RenderImage:renderWebpImageFile("non_existent.webp")
      assert.is_nil(result)
    end
  end)

  it(
    "should handle scaleBlitBuffer with legacy_image_scaling enabled and disabled",
    function()
      local orig_bb = Blitbuffer.new(20, 20)
      G_reader_settings:save("legacy_image_scaling", true)
      local scaled1 = RenderImage:scaleBlitBuffer(orig_bb, 40, 40, false)
      assert.is_not_nil(scaled1)
      assert.are.equal(40, scaled1:getWidth())
      assert.are.equal(40, scaled1:getHeight())
      scaled1:free()

      G_reader_settings:save("legacy_image_scaling", false)
      local scaled2 = RenderImage:scaleBlitBuffer(orig_bb, 30, 30, false)
      assert.is_not_nil(scaled2)
      assert.are.equal(30, scaled2:getWidth())
      assert.are.equal(30, scaled2:getHeight())
      scaled2:free()
      orig_bb:free()
      G_reader_settings:delete("legacy_image_scaling")
    end
  )

  it("should handle checkerboard rendering for different BB types", function()
    local bb_rgb =
      RenderImage:renderCheckerboard(64, 64, Blitbuffer.TYPE_BBRGB32)
    assert.is_not_nil(bb_rgb)
    assert.are.equal(64, bb_rgb:getWidth())
    assert.are.equal(64, bb_rgb:getHeight())
    bb_rgb:free()

    local bb_8 = RenderImage:renderCheckerboard(32, 32, Blitbuffer.TYPE_BB8)
    assert.is_not_nil(bb_8)
    assert.are.equal(32, bb_8:getWidth())
    bb_8:free()

    -- Test default dimensions (800x800)
    local bb_default = RenderImage:renderCheckerboard()
    assert.is_not_nil(bb_default)
    assert.are.equal(800, bb_default:getWidth())
    assert.are.equal(800, bb_default:getHeight())
    bb_default:free()
  end)

  it(
    "should handle scaleBlitBuffer when dimensions are nil or identical",
    function()
      local orig_bb = Blitbuffer.new(50, 50)
      local same1 = RenderImage:scaleBlitBuffer(orig_bb, nil, 50)
      assert.are.equal(orig_bb, same1)

      local same2 = RenderImage:scaleBlitBuffer(orig_bb, 50, nil)
      assert.are.equal(orig_bb, same2)

      local same3 = RenderImage:scaleBlitBuffer(orig_bb, 50, 50)
      assert.are.equal(orig_bb, same3)

      orig_bb:free()
    end
  )

  it("should handle renderSVGImageFile with MuPDF backend", function()
    local tmp_svg = os.tmpname()
    local f = io.open(tmp_svg, "w")
    f:write(
      '<svg viewBox="0 0 100 100" width="100" height="100"><circle cx="50" cy="50" r="40" fill="red" /></svg>'
    )
    f:close()

    RenderImage.RENDER_SVG_WITH_NANOSVG = false
    local bb = RenderImage:renderSVGImageFile(tmp_svg, 50, 50)
    if bb then
      assert.is_not_nil(bb)
      bb:free()
    end

    -- Test with zoom specified
    local bb_zoom = RenderImage:renderSVGImageFile(tmp_svg, nil, nil, 2.0)
    if bb_zoom then
      bb_zoom:free()
    end

    -- Test with width only
    local bb_w = RenderImage:renderSVGImageFile(tmp_svg, 80, nil)
    if bb_w then
      bb_w:free()
    end

    -- Test with height only
    local bb_h = RenderImage:renderSVGImageFile(tmp_svg, nil, 80)
    if bb_h then
      bb_h:free()
    end

    -- Test NanoSVG with zoom
    RenderImage.RENDER_SVG_WITH_NANOSVG = true
    local bb_nano_zoom = RenderImage:renderSVGImageFile(tmp_svg, nil, nil, 1.5)
    if bb_nano_zoom then
      bb_nano_zoom:free()
    end

    local bb_nano_w = RenderImage:renderSVGImageFile(tmp_svg, 60, nil)
    if bb_nano_w then
      bb_nano_w:free()
    end

    local bb_nano_h = RenderImage:renderSVGImageFile(tmp_svg, nil, 60)
    if bb_nano_h then
      bb_nano_h:free()
    end

    os.remove(tmp_svg)
  end)

  it("should handle animated GIF frames object creation and cleanup", function()
    local mock_page = {
      image_bb = Blitbuffer.new(10, 10),
    }
    local closed_gif = false
    local mock_gif = {
      getPages = function()
        return 3
      end,
      openPage = function(self, idx)
        return mock_page
      end,
      close = function()
        closed_gif = true
      end,
    }

    local Pic = require("ffi/pic")
    local orig_open_gif = Pic.openGIFDocumentFromData
    Pic.openGIFDocumentFromData = function(data, size)
      return mock_gif
    end

    local dummy_gif_data = "GIF89aDummy"
    local frames =
      RenderImage:renderImageData(dummy_gif_data, #dummy_gif_data, true, 20, 20)
    assert.is_table(frames)
    assert.is_true(frames.image_disposable)
    assert.is_true(frames.gif_close_needed)
    assert.are.equal(3, #frames)

    -- Invoke frame generator
    local frame1_bb = frames[1]()
    assert.is_not_nil(frame1_bb)
    assert.are.equal(20, frame1_bb:getWidth())
    assert.are.equal(20, frame1_bb:getHeight())
    frame1_bb:free()

    -- Free frames structure
    frames:free()
    assert.is_true(closed_gif)

    mock_page.image_bb:free()
    Pic.openGIFDocumentFromData = orig_open_gif
  end)

  it(
    "should handle animated WebP frames object creation and cleanup",
    function()
      local mock_webp_bb = Blitbuffer.new(15, 15)
      local closed_webp = false
      local mock_webp = {
        nb_frames = 2,
        getFrameImage = function(self, idx, no_copy)
          return mock_webp_bb
        end,
        close = function()
          closed_webp = true
        end,
      }

      local WebP = require("ffi/webp")
      local orig_from_data = WebP.fromData
      WebP.fromData = function(data, size)
        return mock_webp
      end

      local dummy_webp_data = "RIFF1234WEBPVP8"
      local frames = RenderImage:renderImageData(
        dummy_webp_data,
        #dummy_webp_data,
        true,
        30,
        30
      )
      assert.is_table(frames)
      assert.is_true(frames.image_disposable)
      assert.is_true(frames.webp_close_needed)
      assert.are.equal(2, #frames)

      -- Invoke frame generator
      local frame1_bb = frames[1]()
      assert.is_not_nil(frame1_bb)
      assert.are.equal(30, frame1_bb:getWidth())
      assert.are.equal(30, frame1_bb:getHeight())
      frame1_bb:free()

      -- Free frames structure
      frames:free()
      assert.is_true(closed_webp)

      mock_webp_bb:free()
      WebP.fromData = orig_from_data
    end
  )
end)
