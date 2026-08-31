describe("ImageWidget module", function()
  local ImageWidget, Blitbuffer, Geom, Screen

  setup(function()
    require("commonrequire")
    ImageWidget = require("ui/widget/imagewidget")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
    Screen = require("device").screen
  end)

  it("should render without error from file and handle cleanCache", function()
    local imgw = ImageWidget:new({
      file = "resources/koreader.png",
    })
    imgw:_render()
    assert.is_not_nil(imgw._bb)
    assert.is_number(imgw:getSize().w)
    assert.is_number(imgw:getSize().h)

    assert.has_no.errors(function()
      ImageWidget:cleanCache()
      ImageWidget:checkCache()
    end)
  end)

  it("handles rotation, scaling, stretching, and invert options", function()
    -- Rotation 90, 180, 270
    for _, angle in ipairs({ 90, 180, 270 }) do
      local img_rot = ImageWidget:new({
        file = "resources/koreader.png",
        rotation_angle = angle,
      })
      img_rot:_render()
      assert.is_not_nil(img_rot._bb)
    end

    -- Scale factor 0.5
    local img_scale = ImageWidget:new({
      file = "resources/koreader.png",
      scale_factor = 0.5,
      invert = true,
    })
    img_scale:_render()
    assert.is_not_nil(img_scale._bb)

    -- Best fit (scale_factor = 0)
    local img_fit = ImageWidget:new({
      file = "resources/koreader.png",
      width = 100,
      height = 100,
      scale_factor = 0,
    })
    img_fit:_render()
    assert.is_not_nil(img_fit._bb)
    assert.is_number(img_fit:getScaleFactor())

    -- Stretch mode and stretch limit percentage
    local img_stretch = ImageWidget:new({
      file = "resources/koreader.png",
      width = 200,
      height = 200,
      stretch_limit_percentage = 20,
    })
    img_stretch:_render()
    assert.is_not_nil(img_stretch._bb)

    -- Scale for DPI
    local img_dpi = ImageWidget:new({
      file = "resources/koreader.png",
      scale_for_dpi = true,
    })
    img_dpi:_render()
    assert.is_not_nil(img_dpi._bb)
  end)

  it("handles memory Blitbuffer input and setters", function()
    local mem_bb = Blitbuffer.new(50, 50)
    local imgw = ImageWidget:new({
      image = mem_bb,
      image_disposable = false,
    })
    imgw:_render()
    assert.is_not_nil(imgw._bb)

    -- Setters
    imgw:setDimensions(120, 120)
    assert.are.equal(120, imgw.width)
    assert.are.equal(120, imgw.height)

    imgw:setDimen(Geom:new({ w = 80, h = 80 }))
    assert.are.equal(80, imgw.width)
    assert.are.equal(80, imgw.height)

    imgw:setScaleFactor(1.5)
    assert.are.equal(1.5, imgw.scale_factor)

    imgw:setRotationAngle(90)
    assert.are.equal(90, imgw.rotation_angle)

    local new_bb = Blitbuffer.new(60, 60)
    imgw:setImage(new_bb, false)
    assert.are.equal(new_bb, imgw.image)

    imgw:setFile("resources/koreader.png")
    assert.are.equal("resources/koreader.png", imgw.file)
  end)

  it("handles panning, dimension getters, and paintTo variations", function()
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

    -- paintTo normal, dim, invert, alpha, and night mode
    local test_bb = Blitbuffer.new(200, 200)
    imgw.dim = true
    imgw.invert = true
    imgw:paintTo(test_bb, 0, 0)

    -- Alpha straight and premultiplied
    imgw.alpha = true
    imgw._is_straight_alpha = true
    imgw:paintTo(test_bb, 0, 0)

    imgw._is_straight_alpha = false
    imgw:paintTo(test_bb, 0, 0)

    -- SW dithering
    local old_dithering = Screen.sw_dithering
    Screen.sw_dithering = true
    imgw:paintTo(test_bb, 0, 0)
    imgw.alpha = false
    imgw:paintTo(test_bb, 0, 0)
    Screen.sw_dithering = old_dithering

    -- Night mode
    local old_night = Screen.night_mode
    Screen.night_mode = true
    imgw.original_in_nightmode = true
    imgw.is_icon = false
    imgw:paintTo(test_bb, 0, 0)

    imgw.is_icon = true
    imgw:paintTo(test_bb, 0, 0)
    Screen.night_mode = old_night

    -- Hide
    imgw.hide = true
    assert.has_no.errors(function()
      imgw:paintTo(test_bb, 0, 0)
    end)

    -- onClose and free
    imgw:onClose()
  end)
end)

