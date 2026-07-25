describe("BBoxWidget widget module", function()
  local BBoxWidget, Geom

  setup(function()
    require("commonrequire")
    BBoxWidget = require("ui/widget/bboxwidget")
    Geom = require("ui/geometry")
  end)

  it("should initialize BBoxWidget instance", function()
    local mock_document = {
      getPageBBox = function()
        return { x = 0, y = 0, w = 100, h = 100 }
      end,
      getPageDimensions = function()
        return { w = 100, h = 100 }
      end,
    }
    local mock_view = {
      state = { page = 1 },
      dimen = Geom:new({ w = 600, h = 800 }),
      pageToScreenBBox = function()
        return { x = 0, y = 0, w = 100, h = 100 }
      end,
      screenToPageBBox = function()
        return { x = 0, y = 0, w = 100, h = 100 }
      end,
    }

    local widget = BBoxWidget:new({
      document = mock_document,
      view = mock_view,
    })
    assert.is_table(widget)
    assert.is_table(widget.page_bbox)
  end)
end)
