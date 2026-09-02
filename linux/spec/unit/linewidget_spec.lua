describe("LineWidget", function()
  local LineWidget
  local Geom
  local Blitbuffer

  setup(function()
    require("commonrequire")
    LineWidget = require("ui/widget/linewidget")
    Geom = require("ui/geometry")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should create LineWidget with default properties", function()
    local line = LineWidget:new({
      dimen = Geom:new({ w = 100, h = 2 }),
    })
    assert.are.equal("solid", line.style)
    assert.are.equal(Blitbuffer.COLOR_BLACK, line.background)
    assert.are.equal(100, line:getSize().w)
    assert.are.equal(2, line:getSize().h)
  end)

  it("should paint solid line without empty segments", function()
    local line = LineWidget:new({
      dimen = Geom:new({ w = 100, h = 4 }),
      background = Blitbuffer.COLOR_GRAY,
    })

    local painted = {}
    local mock_bb = {
      paintRect = function(self, px, py, pw, ph, pcolor)
        table.insert(painted, { x = px, y = py, w = pw, h = ph, color = pcolor })
      end,
    }

    line:paintTo(mock_bb, 10, 20)
    assert.are.equal(1, #painted)
    assert.are.same({ x = 10, y = 20, w = 100, h = 4, color = Blitbuffer.COLOR_GRAY }, painted[1])
  end)

  it("should paint solid line with empty segments", function()
    local line = LineWidget:new({
      dimen = Geom:new({ w = 100, h = 2 }),
      empty_segments = {
        { s = 30, e = 50 },
      },
    })

    local painted = {}
    local mock_bb = {
      paintRect = function(self, px, py, pw, ph, pcolor)
        table.insert(painted, { x = px, y = py, w = pw, h = ph, color = pcolor })
      end,
    }

    line:paintTo(mock_bb, 0, 10)
    assert.are.equal(2, #painted)
    assert.are.same({ x = 0, y = 10, w = 30, h = 2, color = Blitbuffer.COLOR_BLACK }, painted[1])
    assert.are.same({ x = 50, y = 10, w = 50, h = 2, color = Blitbuffer.COLOR_BLACK }, painted[2])
  end)

  it("should paint dashed line", function()
    local line = LineWidget:new({
      dimen = Geom:new({ w = 65, h = 3 }),
      style = "dashed",
    })

    local painted = {}
    local mock_bb = {
      paintRect = function(self, px, py, pw, ph, pcolor)
        table.insert(painted, { x = px, y = py, w = pw, h = ph, color = pcolor })
      end,
    }

    line:paintTo(mock_bb, 5, 15)
    -- For w = 65, loop for i = 0, 65 - 20 (45), step 20: i = 0, 20, 40 (3 iterations)
    assert.are.equal(3, #painted)
    assert.are.same({ x = 5, y = 15, w = 16, h = 3, color = Blitbuffer.COLOR_BLACK }, painted[1])
    assert.are.same({ x = 25, y = 15, w = 16, h = 3, color = Blitbuffer.COLOR_BLACK }, painted[2])
    assert.are.same({ x = 45, y = 15, w = 16, h = 3, color = Blitbuffer.COLOR_BLACK }, painted[3])
  end)

  it("should not paint when style is none", function()
    local line = LineWidget:new({
      dimen = Geom:new({ w = 100, h = 2 }),
      style = "none",
    })

    local paint_called = false
    local mock_bb = {
      paintRect = function()
        paint_called = true
      end,
    }

    line:paintTo(mock_bb, 0, 0)
    assert.is_false(paint_called)
  end)
end)
