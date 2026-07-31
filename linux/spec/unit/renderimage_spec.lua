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
end)
