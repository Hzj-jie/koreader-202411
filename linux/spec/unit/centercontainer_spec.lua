describe("CenterContainer", function()
  local CenterContainer
  local Geom
  local Widget

  setup(function()
    require("commonrequire")
    CenterContainer = require("ui/widget/container/centercontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should center content horizontally and vertically by default", function()
    local painted_x, painted_y
    local child = Widget:new({
      dimen = Geom:new({ w = 40, h = 20 }),
      paintTo = function(self, bb, x, y)
        painted_x = x
        painted_y = y
      end,
    })

    local cc = CenterContainer:new({
      dimen = Geom:new({ w = 100, h = 80 }),
      child,
    })

    cc:paintTo(nil, 10, 10)
    -- Expected x: 10 + (100 - 40)/2 = 10 + 30 = 40
    -- Expected y: 10 + (80 - 20)/2 = 10 + 30 = 40
    assert.are.equal(40, painted_x)
    assert.are.equal(40, painted_y)
  end)

  it("should respect explicit ignore settings", function()
    local painted_x, painted_y
    local child = Widget:new({
      dimen = Geom:new({ w = 40, h = 20 }),
      paintTo = function(self, bb, x, y)
        painted_x = x
        painted_y = y
      end,
    })

    -- ignore width
    local cc_ignore_w = CenterContainer:new({
      dimen = Geom:new({ w = 100, h = 80 }),
      ignore = "width",
      child,
    })
    cc_ignore_w:paintTo(nil, 0, 0)
    assert.are.equal(0, painted_x)
    assert.are.equal(30, painted_y)

    -- ignore height
    local cc_ignore_h = CenterContainer:new({
      dimen = Geom:new({ w = 100, h = 80 }),
      ignore = "height",
      child,
    })
    cc_ignore_h:paintTo(nil, 0, 0)
    assert.are.equal(30, painted_x)
    assert.are.equal(0, painted_y)
  end)

  it("should center dynamically when container size changes with ignore_if_over", function()
    local dummy_widget = {
      getSize = function(self)
        return self.dimen
      end,
      paintTo = function(self, _bb, x, y)
        self.painted_x = x
        self.painted_y = y
      end,
      dimen = { w = 20, h = 20 },
    }
    local cc = CenterContainer:new({
      dummy_widget,
      ignore_if_over = "height",
      dimen = { w = 40, h = 10 }, -- Container height (10) < content height (20)
    })

    -- Frame 1: Container is smaller than content, should ignore height centering (align top)
    cc:paintTo(nil, 0, 0)
    assert.is_equal(0, dummy_widget.painted_y) -- should be at y=0 (top aligned)

    -- Frame 2: Container becomes larger than content, should center height
    cc.dimen = { w = 40, h = 40 } -- Container height (40) > content height (20)
    cc:paintTo(nil, 0, 0)
    -- Expected y: (40 - 20) / 2 = 10
    assert.is_equal(10, dummy_widget.painted_y)

    -- Test ignore_if_over = "width"
    local cc_w = CenterContainer:new({
      dummy_widget,
      ignore_if_over = "width",
      dimen = { w = 10, h = 40 },
    })
    cc_w:paintTo(nil, 0, 0)
    assert.is_equal(0, dummy_widget.painted_x)

    cc_w.dimen = { w = 40, h = 40 }
    cc_w:paintTo(nil, 0, 0)
    assert.is_equal(10, dummy_widget.painted_x)
  end)

  it("should delegate dirtyRegion to child", function()
    local child = Widget:new({
      dirty_dimen = Geom:new({ x = 5, y = 5, w = 50, h = 50 }),
    })
    local cc = CenterContainer:new({ child })
    local region = cc:dirtyRegion()
    assert.are.equal(50, region.w)
    assert.are.equal(50, region.h)
  end)
end)
