local spy = require("luassert.spy")

describe("ImageViewer", function()
  local ImageViewer
  local UIManager
  local ImageWidget
  local Widget
  local Geom

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ImageViewer = require("ui/widget/imageviewer")
    UIManager = require("ui/uimanager")
    ImageWidget = require("ui/widget/imagewidget")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")

    local DummyImageWidget = Widget:extend()
    function DummyImageWidget:init()
      self.dimen = Geom:new({ w = 100, h = 100 })
    end
    function DummyImageWidget:getCurrentHeight()
      return 100
    end
    function DummyImageWidget:getCurrentWidth()
      return 100
    end
    function DummyImageWidget:getScaleFactor()
      return 1
    end
    function DummyImageWidget:getOriginalHeight()
      return 100
    end
    function DummyImageWidget:getOriginalWidth()
      return 100
    end
    function DummyImageWidget:getScaleFactorExtrema()
      return 0.5, 2.0
    end
    function DummyImageWidget:getPanByCenterRatio()
      return 0, 0
    end
    function DummyImageWidget:getCurrentDiagonal()
      return 141
    end
    function DummyImageWidget:free() end

    stub(ImageWidget, "new", function(self, _args)
      return DummyImageWidget:new()
    end)
  end)

  teardown(function()
    ImageWidget.new:revert()
  end)

  it("opens image file directly", function()
    spy.on(UIManager, "show")

    ImageViewer:openFile("dummy_image.png")

    assert.spy(UIManager.show).was.called(1)
    local widget = UIManager.show.calls[1].refs[2]
    assert.is_not_nil(widget)
    assert.equal("dummy_image.png", widget.file)

    UIManager:close(widget)
    UIManager.show:revert()
  end)

  it("should handle navigation across image list", function()
    local viewer = ImageViewer:new({
      image = { "img1", "img2", "img3" },
      image_index = 1,
    })

    if type(viewer.onShowNextImage) == "function" then
      viewer:onShowNextImage()
    end
    if type(viewer.onShowPrevImage) == "function" then
      viewer:onShowPrevImage()
    end
  end)

  it("should toggle fullscreen and buttons visibility", function()
    local viewer = ImageViewer:new({
      file = "dummy.png",
      fullscreen = false,
      buttons_visible = false,
    })

    if type(viewer.onToggleFullscreen) == "function" then
      viewer:onToggleFullscreen()
      assert.is_true(viewer.fullscreen)
    end

    if type(viewer.onToggleButtons) == "function" then
      viewer:onToggleButtons()
      assert.is_true(viewer.buttons_visible)
    end
  end)

  it("should handle dispatcher actions and zoom operations", function()
    local viewer = ImageViewer:new({ file = "dummy.png" })

    if type(viewer.onDispatcherRegisterActions) == "function" then
      viewer:onDispatcherRegisterActions()
    end

    if type(viewer.onZoomIn) == "function" then
      viewer:onZoomIn()
    end
    if type(viewer.onZoomOut) == "function" then
      viewer:onZoomOut()
    end
  end)
end)
