local spy = require("luassert.spy")
local mock = require("luassert.mock")

describe("ImageViewer", function()
  local ImageViewer
  local UIManager
  local ImageWidget
  local Widget
  local Geom

  setup(function()
    require("commonrequire")
    ImageViewer = require("ui/widget/imageviewer")
    UIManager = require("ui/uimanager")
    ImageWidget = require("ui/widget/imagewidget")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")

    -- Mock ImageWidget to avoid loading real images / FFI stuff
    local DummyImageWidget = Widget:extend()
    function DummyImageWidget:init()
      self.dimen = Geom:new({ w = 100, h = 100 })
    end
    function DummyImageWidget:getCurrentHeight() return 100 end
    function DummyImageWidget:getCurrentWidth() return 100 end
    function DummyImageWidget:getScaleFactor() return 1 end
    function DummyImageWidget:getOriginalHeight() return 100 end
    function DummyImageWidget:getOriginalWidth() return 100 end
    function DummyImageWidget:getScaleFactorExtrema() return 0.5, 2.0 end
    function DummyImageWidget:getPanByCenterRatio() return 0, 0 end
    function DummyImageWidget:getCurrentDiagonal() return 141 end

    stub(ImageWidget, "new", function(self, args)
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
end)
