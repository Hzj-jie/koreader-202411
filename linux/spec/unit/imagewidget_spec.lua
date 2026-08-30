describe("ImageWidget module", function()
  local ImageWidget
  setup(function()
    require("commonrequire")
    ImageWidget = require("ui/widget/imagewidget")
  end)

  it("should render without error", function()
    local imgw = ImageWidget:new({
      file = "resources/koreader.png",
    })
    imgw:_render()
    assert(imgw._bb)
  end)

  it("handles rotation, scaling, stretching, and invert options", function()
    -- Rotation 90
    local img_rot = ImageWidget:new({
      file = "resources/koreader.png",
      rotation_angle = 90,
    })
    img_rot:_render()
    assert.is_not_nil(img_rot._bb)

    -- Scale factor 0.5
    local img_scale = ImageWidget:new({
      file = "resources/koreader.png",
      scale_factor = 0.5,
      invert = true,
    })
    img_scale:_render()
    assert.is_not_nil(img_scale._bb)

    -- Stretch mode
    local img_stretch = ImageWidget:new({
      file = "resources/koreader.png",
      width = 200,
      height = 200,
      stretch = true,
    })
    img_stretch:_render()
    assert.is_not_nil(img_stretch._bb)
  end)

  it("handles panning, dimension getters, and paintTo", function()
    local imgw = ImageWidget:new({
      file = "resources/koreader.png",
      scale_factor = 2.0,
      width = 100,
      height = 100,
    })
    imgw:_render()

    -- Dimension getters
    assert.is_number(imgw:getCurrentWidth())
    assert.is_number(imgw:getCurrentHeight())
    assert.is_number(imgw:getCurrentDiagonal())
    assert.is_number(imgw:getScaleFactor())

    local min_f, max_f = imgw:getScaleFactorExtrema()
    assert.is_number(min_f)
    assert.is_number(max_f)

    -- Panning
    local rx, ry = imgw:getPanByCenterRatio(10, 10)
    assert.is_number(rx)
    assert.is_number(ry)
    imgw:panBy(5, 5)

    -- paintTo
    local Screen = require("device").screen
    imgw:paintTo(Screen.bb, 0, 0)

    imgw:free()
  end)
end)

