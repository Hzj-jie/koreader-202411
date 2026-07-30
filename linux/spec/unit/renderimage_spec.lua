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

  it("should handle corrupted image header gracefully", function()
    local corrupted_data = "CORRUPTED_HEADER_DATA_12345"
    local result = RenderImage:renderImageData(corrupted_data, #corrupted_data)
    assert.is_nil(result)
  end)

  it("should validate supported image files and dimensions", function()
    if type(RenderImage.isSupportedImageFile) == "function" then
      assert.is_boolean(RenderImage:isSupportedImageFile("test.png"))
      assert.is_false(RenderImage:isSupportedImageFile("test.txt"))
    end
  end)
end)
