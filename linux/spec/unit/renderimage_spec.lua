local RenderImage = require("ui/renderimage")

describe("RenderImage module", function()
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
end)
