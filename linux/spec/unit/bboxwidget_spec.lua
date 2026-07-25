describe("BBoxWidget widget module", function()
  local BBoxWidget, Device, Geom, Math, Size, UIManager

  setup(function()
    require("commonrequire")
    BBoxWidget = require("ui/widget/bboxwidget")
    Device = require("device")
    Geom = require("ui/geometry")
    Math = require("optmath")
    Size = require("ui/size")
    UIManager = require("ui/uimanager")
  end)

  local function createMockViewAndDoc()
    local mock_document = {
      getPageBBox = function(self, page)
        return { x0 = 10, y0 = 20, x1 = 100, y1 = 200 }
      end,
      getPageDimensions = function(self)
        return { w = 600, h = 800 }
      end,
    }
    local mock_view = {
      state = {
        page = 1,
        zoom = 1.0,
        offset = { x = 0, y = 0 },
      },
      dimen = Geom:new({ w = 600, h = 800 }),
      page_area = Geom:new({ x = 0, y = 0, w = 600, h = 800 }),
      getSize = function(self)
        return Geom:new({ w = 600, h = 800 })
      end,
      pageToScreenBBox = function(self, bbox)
        return bbox
      end,
      screenToPageBBox = function(self, bbox)
        return bbox
      end,
    }
    return mock_document, mock_view
  end

  it("should initialize BBoxWidget instance", function()
    local mock_document, mock_view = createMockViewAndDoc()
    local widget = BBoxWidget:new({
      document = mock_document,
      view = mock_view,
    })
    assert.is_table(widget)
    assert.is_table(widget.page_bbox)
    assert.are.same({ x0 = 10, y0 = 20, x1 = 100, y1 = 200 }, widget.page_bbox)
    assert.is_table(widget.dimen)
  end)

  describe("coordinate transformations", function()
    it(
      "should transform page bbox to screen bbox with zoom and offset",
      function()
        local mock_document, mock_view = createMockViewAndDoc()
        mock_view.state.zoom = 2.0
        mock_view.state.offset = { x = 50, y = 100 }

        local widget = BBoxWidget:new({
          document = mock_document,
          view = mock_view,
        })

        local page_bbox = { x0 = 10, y0 = 20, x1 = 100, y1 = 200 }
        local screen_bbox = widget:getScreenBBox(page_bbox)

        assert.are.same({ x0 = 70, y0 = 140, x1 = 250, y1 = 500 }, screen_bbox)
      end
    )

    it(
      "should transform screen bbox to page bbox with zoom and offset",
      function()
        local mock_document, mock_view = createMockViewAndDoc()
        mock_view.state.zoom = 2.0
        mock_view.state.offset = { x = 50, y = 100 }

        local widget = BBoxWidget:new({
          document = mock_document,
          view = mock_view,
        })

        local screen_bbox = { x0 = 70, y0 = 140, x1 = 250, y1 = 500 }
        local page_bbox = widget:getPageBBox(screen_bbox)

        assert.are.same({ x0 = 10, y0 = 20, x1 = 100, y1 = 200 }, page_bbox)
      end
    )

    it("should get modified page bbox from screen_bbox", function()
      local mock_document, mock_view = createMockViewAndDoc()
      local widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget.screen_bbox = { x0 = 20, y0 = 40, x1 = 200, y1 = 400 }
      local mod_page_bbox = widget:getModifiedPageBBox()
      assert.are.same({ x0 = 20, y0 = 40, x1 = 200, y1 = 400 }, mod_page_bbox)
    end)
  end)

  describe("inPageArea", function()
    it(
      "should correctly test if gesture position is within page area",
      function()
        local mock_document, mock_view = createMockViewAndDoc()
        local widget = BBoxWidget:new({
          document = mock_document,
          view = mock_view,
        })

        local inside_ges = { pos = Geom:new({ x = 300, y = 400 }) }
        local outside_ges = { pos = Geom:new({ x = 700, y = 900 }) }

        assert.is_true(widget:inPageArea(inside_ges))
        assert.is_false(widget:inPageArea(outside_ges))
      end
    )
  end)

  describe("adjustScreenBBox (absolute adjustment)", function()
    local widget, mock_document, mock_view

    before_each(function()
      mock_document, mock_view = createMockViewAndDoc()
      widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget.screen_bbox = { x0 = 100, y0 = 100, x1 = 500, y1 = 500 }
    end)

    it("should adjust upper_left corner when tapping near top-left", function()
      local ges = { pos = Geom:new({ x = 90, y = 95 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 90, y0 = 95, x1 = 500, y1 = 500 },
        widget.screen_bbox
      )
    end)

    it(
      "should adjust bottom_right corner when tapping near bottom-right",
      function()
        local ges = { pos = Geom:new({ x = 510, y = 505 }) }
        widget:onTapAdjust(nil, ges)
        assert.are.same(
          { x0 = 100, y0 = 100, x1 = 510, y1 = 505 },
          widget.screen_bbox
        )
      end
    )

    it(
      "should adjust upper_right corner when tapping near top-right",
      function()
        local ges = { pos = Geom:new({ x = 495, y = 90 }) }
        widget:onTapAdjust(nil, ges)
        assert.are.same(
          { x0 = 100, y0 = 90, x1 = 495, y1 = 500 },
          widget.screen_bbox
        )
      end
    )

    it(
      "should adjust bottom_left corner when tapping near bottom-left",
      function()
        local ges = { pos = Geom:new({ x = 105, y = 495 }) }
        widget:onTapAdjust(nil, ges)
        assert.are.same(
          { x0 = 105, y0 = 100, x1 = 500, y1 = 495 },
          widget.screen_bbox
        )
      end
    )

    it("should adjust top edge when tapping near upper_center", function()
      local ges = { pos = Geom:new({ x = 300, y = 80 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 100, y0 = 80, x1 = 500, y1 = 500 },
        widget.screen_bbox
      )
    end)

    it("should adjust bottom edge when tapping near bottom_center", function()
      local ges = { pos = Geom:new({ x = 300, y = 520 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 100, y0 = 100, x1 = 500, y1 = 520 },
        widget.screen_bbox
      )
    end)

    it("should adjust left edge when tapping near left_center", function()
      local ges = { pos = Geom:new({ x = 80, y = 300 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 80, y0 = 100, x1 = 500, y1 = 500 },
        widget.screen_bbox
      )
    end)

    it("should adjust right edge when tapping near right_center", function()
      local ges = { pos = Geom:new({ x = 520, y = 300 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 100, y0 = 100, x1 = 520, y1 = 500 },
        widget.screen_bbox
      )
    end)

    it("should ignore gesture outside page area", function()
      local ges = { pos = Geom:new({ x = 700, y = 900 }) }
      widget:onTapAdjust(nil, ges)
      assert.are.same(
        { x0 = 100, y0 = 100, x1 = 500, y1 = 500 },
        widget.screen_bbox
      )
    end)
  end)

  describe("adjustScreenBBox (relative swipe adjustment)", function()
    local widget, mock_document, mock_view

    before_each(function()
      mock_document, mock_view = createMockViewAndDoc()
      widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget.screen_bbox = { x0 = 100, y0 = 100, x1 = 500, y1 = 500 }
      widget.fine_factor = 10
    end)

    it(
      "should adjust upper edge relatively on upper_center swipe north/south",
      function()
        local ges_south = {
          pos = Geom:new({ x = 300, y = 100 }),
          direction = "south",
          distance = 50,
        }
        widget:onSwipeAdjust(nil, ges_south)
        assert.are.equal(105, widget.screen_bbox.y0)

        local ges_north = {
          pos = Geom:new({ x = 300, y = 105 }),
          direction = "north",
          distance = 30,
        }
        widget:onSwipeAdjust(nil, ges_north)
        assert.are.equal(102, widget.screen_bbox.y0)
      end
    )

    it(
      "should adjust right edge relatively on right_center swipe east/west",
      function()
        local ges_east = {
          pos = Geom:new({ x = 500, y = 300 }),
          direction = "east",
          distance = 40,
        }
        widget:onSwipeAdjust(nil, ges_east)
        assert.are.equal(504, widget.screen_bbox.x1)

        local ges_west = {
          pos = Geom:new({ x = 504, y = 300 }),
          direction = "west",
          distance = 20,
        }
        widget:onSwipeAdjust(nil, ges_west)
        assert.are.equal(502, widget.screen_bbox.x1)
      end
    )

    it(
      "should adjust bottom edge relatively on bottom_center swipe north/south",
      function()
        local ges_south = {
          pos = Geom:new({ x = 300, y = 500 }),
          direction = "south",
          distance = 60,
        }
        widget:onSwipeAdjust(nil, ges_south)
        assert.are.equal(506, widget.screen_bbox.y1)
      end
    )

    it(
      "should adjust left edge relatively on left_center swipe east/west",
      function()
        local ges_east = {
          pos = Geom:new({ x = 100, y = 300 }),
          direction = "east",
          distance = 70,
        }
        widget:onSwipeAdjust(nil, ges_east)
        assert.are.equal(107, widget.screen_bbox.x0)
      end
    )
  end)

  describe("onMoveIndicator", function()
    local widget, mock_document, mock_view

    before_each(function()
      mock_document, mock_view = createMockViewAndDoc()
      widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget.screen_bbox = { x0 = 100, y0 = 100, x1 = 500, y1 = 500 }
    end)

    it("should move top-left indicator when _confirm_stage is 1", function()
      widget._confirm_stage = 1
      local step = Size.item.height_default / 4
      local res = widget:onMoveIndicator({ 1, 2 })
      assert.is_true(res)
      assert.are.equal(Math.round(100 + step), widget.screen_bbox.x0)
      assert.are.equal(Math.round(100 + 2 * step), widget.screen_bbox.y0)
    end)

    it(
      "should clamp top-left indicator to max bounds when _confirm_stage is 1",
      function()
        widget._confirm_stage = 1
        widget:onMoveIndicator({ 1000, 1000 })
        local max_x = widget.screen_bbox.x1 - Size.item.height_default
        local max_y = widget.screen_bbox.y1 - Size.item.height_default
        assert.are.equal(max_x, widget.screen_bbox.x0)
        assert.are.equal(max_y, widget.screen_bbox.y0)
      end
    )

    it("should move bottom-right indicator when _confirm_stage is 2", function()
      widget._confirm_stage = 2
      local step = Size.item.height_default / 4
      local res = widget:onMoveIndicator({ -1, -2 })
      assert.is_true(res)
      assert.are.equal(Math.round(500 - step), widget.screen_bbox.x1)
      assert.are.equal(Math.round(500 - 2 * step), widget.screen_bbox.y1)
    end)

    it(
      "should clamp bottom-right indicator to min bounds when _confirm_stage is 2",
      function()
        widget._confirm_stage = 2
        widget:onMoveIndicator({ -1000, -1000 })
        local min_x = widget.screen_bbox.x0 + Size.item.height_default
        local min_y = widget.screen_bbox.y0 + Size.item.height_default
        assert.are.equal(min_x, widget.screen_bbox.x1)
        assert.are.equal(min_y, widget.screen_bbox.y1)
      end
    )
  end)

  describe("events and confirmation flow", function()
    local widget, mock_document, mock_view

    before_each(function()
      mock_document, mock_view = createMockViewAndDoc()
      widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget.screen_bbox = { x0 = 100, y0 = 100, x1 = 500, y1 = 500 }
      stub(UIManager, "broadcastEvent")
    end)

    after_each(function()
      UIManager.broadcastEvent:revert()
    end)

    it("should advance confirm stage on onSelect if stage is 1", function()
      widget._confirm_stage = 1
      local res = widget:onSelect()
      assert.is_true(res)
      assert.are.equal(2, widget._confirm_stage)
    end)

    it("should broadcast ConfirmPageCrop on onSelect if stage is 2", function()
      widget._confirm_stage = 2
      local res = widget:onSelect()
      assert.is_true(res)
      assert.stub(UIManager.broadcastEvent).was_called(1)
      local ev = UIManager.broadcastEvent.calls[1].refs[2]
      assert.are.equal("onConfirmPageCrop", ev.handler)
    end)

    it(
      "should broadcast ConfirmPageCrop on onConfirmAdjust when in page area",
      function()
        local ges = { pos = Geom:new({ x = 300, y = 300 }) }
        local res = widget:onConfirmAdjust(nil, ges)
        assert.is_true(res)
        assert.stub(UIManager.broadcastEvent).was_called(1)
        local ev = UIManager.broadcastEvent.calls[1].refs[2]
        assert.are.equal("onConfirmPageCrop", ev.handler)
      end
    )

    it("should broadcast CancelPageCrop on onExit", function()
      local res = widget:onExit()
      assert.is_true(res)
      assert.stub(UIManager.broadcastEvent).was_called(1)
      local ev = UIManager.broadcastEvent.calls[1].refs[2]
      assert.are.equal("onCancelPageCrop", ev.handler)
    end)

    it("should handle onHoldAdjust", function()
      assert.is_true(widget:onHoldAdjust())
    end)
  end)

  describe("rendering and dimensions", function()
    it("should calculate size via getSize()", function()
      local mock_document, mock_view = createMockViewAndDoc()
      local widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      local size = widget:getSize()
      assert.are.equal(600, size.w)
      assert.are.equal(800, size.h)
    end)

    it("should render edges and indicators in paintTo", function()
      local mock_document, mock_view = createMockViewAndDoc()
      local widget = BBoxWidget:new({
        document = mock_document,
        view = mock_view,
      })
      widget._confirm_stage = 1

      local invert_rect_calls = {}
      local mock_bb = {
        invertRect = function(self, x, y, w, h)
          table.insert(invert_rect_calls, { x = x, y = y, w = w, h = h })
        end,
      }

      widget:paintTo(mock_bb, 0, 0)

      assert.is_true(#invert_rect_calls >= 6)
    end)
  end)
end)
