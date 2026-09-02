describe("Geometry", function()
  local Geom

  setup(function()
    require("commonrequire")
    Geom = require("ui/geometry")
  end)

  it("should create Geom instance with default and custom properties", function()
    local g_default = Geom:new()
    assert.are.equal(0, g_default.x)
    assert.are.equal(0, g_default.y)
    assert.are.equal(0, g_default.w)
    assert.are.equal(0, g_default.h)

    local g_custom = Geom:new({ x = 10, y = 20, w = 100, h = 200 })
    assert.are.equal(10, g_custom.x)
    assert.are.equal(20, g_custom.y)
    assert.are.equal(100, g_custom.w)
    assert.are.equal(200, g_custom.h)
    assert.are.equal("100x200+10+20", tostring(g_custom))
  end)

  it("should copy Geom object", function()
    local g = Geom:new({ x = 5, y = 15, w = 25, h = 35 })
    local copy = g:copy()
    assert.are.same(g, copy)
    copy.x = 99
    assert.are.equal(5, g.x)
  end)

  it("should offset and scale", function()
    local g = Geom:new({ x = 10, y = 20, w = 50, h = 80 })
    g:offsetBy(5, -5)
    assert.are.equal(15, g.x)
    assert.are.equal(15, g.y)

    g:scaleBy(2, 3)
    assert.are.equal(100, g.w)
    assert.are.equal(240, g.h)

    g:scaleBy(0.5)
    assert.are.equal(50, g.w)
    assert.are.equal(120, g.h)

    g:transformByScale(2, 2)
    assert.are.equal(30, g.x)
    assert.are.equal(30, g.y)
    assert.are.equal(100, g.w)
    assert.are.equal(240, g.h)
  end)

  it("should compute area and check isEmpty", function()
    local g = Geom:new({ w = 10, h = 20 })
    assert.are.equal(200, g:area())
    assert.is_false(g:isEmpty())

    local g_empty = Geom:new({ w = 0, h = 50 })
    assert.are.equal(0, g_empty:area())
    assert.is_true(g_empty:isEmpty())

    local g_nil = Geom:new()
    g_nil.w = nil
    assert.are.equal(0, g_nil:area())
  end)

  it("should combine and intersect geometries", function()
    local g1 = Geom:new({ x = 10, y = 10, w = 50, h = 50 })
    local g2 = Geom:new({ x = 30, y = 30, w = 50, h = 50 })

    local combined = g1:combine(g2)
    assert.are.same({ x = 10, y = 10, w = 70, h = 70 }, { x = combined.x, y = combined.y, w = combined.w, h = combined.h })

    local inter = g1:intersect(g2)
    assert.are.same({ x = 30, y = 30, w = 30, h = 30 }, { x = inter.x, y = inter.y, w = inter.w, h = inter.h })

    local empty_inter = g1:intersect(nil)
    assert.are.same(g1, empty_inter)

    local g3 = Geom:new({ x = 100, y = 100, w = 20, h = 20 })
    assert.is_true(g1:notIntersectWith(g3))
    assert.is_false(g1:intersectWith(g3))
    assert.is_true(g1:notIntersectWith(nil))

    assert.is_false(g1:notIntersectWith(g2))
    assert.is_true(g1:intersectWith(g2))
  end)

  it("should handle setSizeTo, contains, and equality checks", function()
    local g1 = Geom:new({ x = 10, y = 10, w = 100, h = 100 })
    local g2 = Geom:new({ x = 20, y = 20, w = 50, h = 50 })
    local g3 = Geom:new({ x = 10, y = 10, w = 100, h = 100 })

    assert.is_true(g1:contains(g2))
    assert.is_false(g2:contains(g1))
    assert.is_false(g1:contains(nil))

    assert.is_true(g1 == g3)
    assert.is_false(g1 == g2)
    assert.is_true(g1:equalSize(g3))
    assert.is_false(g1:equalSize(g2))

    assert.is_true(g2 < g1)
    assert.is_false(g1 < g2)
    assert.is_true(g2 <= g1)
    assert.is_true(g1 <= g3)

    g2:setSizeTo(g1)
    assert.are.equal(100, g2.w)
    assert.are.equal(100, g2.h)
  end)

  it("should handle offsetWithin, centerWithin, and shrinkInside", function()
    local container = Geom:new({ x = 0, y = 0, w = 200, h = 200 })
    local box = Geom:new({ x = 10, y = 10, w = 50, h = 50 })

    box:offsetWithin(container, 100, 100)
    assert.are.equal(110, box.x)
    assert.are.equal(110, box.y)

    -- Push outside container boundary to trigger clamping
    box:offsetWithin(container, 200, 200)
    assert.are.equal(150, box.x) -- 200 - 50 = 150
    assert.are.equal(150, box.y)

    -- Oversized box
    local huge_box = Geom:new({ x = -50, y = -50, w = 300, h = 300 })
    huge_box:offsetWithin(container, 0, 0)
    assert.are.equal(0, huge_box.x)
    assert.are.equal(0, huge_box.y)
    assert.are.equal(200, huge_box.w)
    assert.are.equal(200, huge_box.h)

    local cbox = Geom:new({ x = 0, y = 0, w = 60, h = 40 })
    cbox:centerWithin(container, 100, 100)
    assert.are.equal(70, cbox.x) -- 100 - 30 = 70
    assert.are.equal(80, cbox.y) -- 100 - 20 = 80

    -- centerOutside clamped
    cbox:centerWithin(container, 0, 0)
    assert.are.equal(0, cbox.x)
    assert.are.equal(0, cbox.y)

    cbox:centerWithin(container, 300, 300)
    assert.are.equal(140, cbox.x)
    assert.are.equal(160, cbox.y)

    local sh_box = Geom:new({ x = 10, y = 10, w = 100, h = 100 })
    local res = sh_box:shrinkInside(container, 5, 5)
    assert.truthy(res)
    assert.are.equal(15, sh_box.x)
  end)

  it("should calculate distance, midpoint, center, clear, and resize", function()
    local p1 = Geom:new({ x = 0, y = 0, w = 0, h = 0 })
    local p2 = Geom:new({ x = 3, y = 4, w = 0, h = 0 })

    assert.are.equal(5, p1:distance(p2))

    local mid = p1:midpoint(p2)
    assert.are.equal(2, mid.x)
    assert.are.equal(2, mid.y)

    local rect = Geom:new({ x = 10, y = 20, w = 100, h = 200 })
    local center = rect:center()
    assert.are.equal(60, center.x)
    assert.are.equal(120, center.y)

    rect:resize({ ratio_x = 0.1, ratio_y = 0.2, ratio_w = 0.5, ratio_h = 0.5 })
    assert.are.equal(20, rect.x) -- 10 + 100*0.1 = 20
    assert.are.equal(60, rect.y) -- 20 + 200*0.2 = 60
    assert.are.equal(50, rect.w)
    assert.are.equal(100, rect.h)

    rect:clear()
    assert.are.equal(0, rect.x)
    assert.are.equal(0, rect.y)
    assert.are.equal(0, rect.w)
    assert.are.equal(0, rect.h)
  end)

  it("should handle boundingBox, smallerThan, and sortPoints", function()
    assert.is_nil(Geom.boundingBox({}))

    local b1 = Geom:new({ x = 10, y = 10, w = 20, h = 20 })
    local b2 = Geom:new({ x = 0, y = 5, w = 50, h = 10 })
    local bbox = Geom.boundingBox({ b1, b2 })
    assert.are.equal(0, bbox.x)
    assert.are.equal(5, bbox.y)
    assert.are.equal(50, bbox.w)
    assert.are.equal(25, bbox.h)

    -- smallerThan
    assert.is_false(Geom.smallerThan(b1, b1))
    local small = Geom:new({ x = 0, y = 0, w = 5, h = 5 })
    local big = Geom:new({ x = 0, y = 0, w = 10, h = 10 })
    assert.is_true(Geom.smallerThan(small, big))
    assert.is_false(Geom.smallerThan(big, small))

    local same_area1 = Geom:new({ x = 1, y = 5, w = 10, h = 10 })
    local same_area2 = Geom:new({ x = 2, y = 5, w = 10, h = 10 })
    assert.is_true(Geom.smallerThan(same_area1, same_area2))
    assert.is_false(Geom.smallerThan(same_area2, same_area1))

    local same_x1 = Geom:new({ x = 1, y = 2, w = 10, h = 10 })
    local same_x2 = Geom:new({ x = 1, y = 4, w = 10, h = 10 })
    assert.is_true(Geom.smallerThan(same_x1, same_x2))
    assert.is_false(Geom.smallerThan(same_x2, same_x1))

    -- sortPoints
    local p_top = Geom:new({ x = 5, y = 10 })
    local p_bot = Geom:new({ x = 2, y = 20 })
    local r1, r2 = Geom.sortPoints(p_top, p_bot)
    assert.are.equal(p_top, r1)
    assert.are.equal(p_bot, r2)

    local r3, r4 = Geom.sortPoints(p_bot, p_top)
    assert.are.equal(p_top, r3)
    assert.are.equal(p_bot, r4)

    local p_left = Geom:new({ x = 5, y = 10 })
    local p_right = Geom:new({ x = 15, y = 10 })
    local s1, s2 = Geom.sortPoints(p_right, p_left)
    assert.are.equal(p_left, s1)
    assert.are.equal(p_right, s2)
  end)
end)
