describe("gesturerange module", function()
  local GestureRange, Geom, time
  setup(function()
    require("commonrequire")
    GestureRange = require("ui/gesturerange")
    Geom = require("ui/geometry")
    time = require("ui/time")
  end)

  it("should match tap event within range", function()
    local g = GestureRange:new({
      ges = "tap",
      range = Geom:new({ x = 0, y = 0, w = 200, h = 200 }),
    })
    assert.truthy(g:match({
      ges = "tap",
      pos = Geom:new({ x = 1, y = 1, w = 0, h = 0 }),
    }))
  end)

  it("should not match tap event outside of range", function()
    local g = GestureRange:new({
      ges = "tap",
      range = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
    })
    assert.falsy(g:match({
      ges = "tap",
      pos = Geom:new({ x = 105, y = 1, w = 0, h = 0 }),
    }))
  end)

  it("should match any event within nil range", function()
    local g = GestureRange:new({
      ges = "tap",
      range = nil,
    })
    assert.truthy(g:match({
      ges = "tap",
      pos = Geom:new({ x = 1, y = 1, w = 1000000000000000000, h = 100 }),
    }))
  end)

  it("should handle range as a function", function()
    local geom = Geom:new({ x = 10, y = 10, w = 50, h = 50 })
    local g = GestureRange:new({
      ges = "tap",
      range = function() return geom end,
    })
    assert.is_true(g:match({
      ges = "tap",
      pos = Geom:new({ x = 20, y = 20, w = 0, h = 0 }),
    }))
    assert.is_false(g:match({
      ges = "tap",
      pos = Geom:new({ x = 100, y = 100, w = 0, h = 0 }),
    }))

    -- When range function returns nil
    local g_nil = GestureRange:new({
      ges = "tap",
      range = function() return nil end,
    })
    assert.is_false(g_nil:match({
      ges = "tap",
      pos = Geom:new({ x = 10, y = 10, w = 0, h = 0 }),
    }))
  end)

  it("should return false when gesture type does not match", function()
    local g = GestureRange:new({
      ges = "tap",
    })
    assert.is_false(g:match({ ges = "hold" }))
  end)

  it("should handle rate limiting", function()
    local g = GestureRange:new({
      ges = "pan",
      rate = 2, -- 2 matches per second -> interval 0.5s = 500000us
    })

    local gs1 = { ges = "pan", time = time.s(1) }
    assert.is_true(g:match(gs1))

    -- Too soon (0.1s later)
    local gs2 = { ges = "pan", time = time.s(1.1) }
    assert.is_false(g:match(gs2))

    -- After interval (0.6s later)
    local gs3 = { ges = "pan", time = time.s(1.7) }
    assert.is_true(g:match(gs3))
  end)

  it("should handle scale limits with distance and span", function()
    local g = GestureRange:new({
      ges = "pinch",
      scale = { 50, 200 },
    })

    assert.is_true(g:match({ ges = "pinch", distance = 100 }))
    assert.is_false(g:match({ ges = "pinch", distance = 30 }))
    assert.is_false(g:match({ ges = "pinch", distance = 250 }))
    assert.is_true(g:match({ ges = "pinch", span = 150 }))
  end)

  it("should handle direction matching", function()
    local g = GestureRange:new({
      ges = "swipe",
      direction = "east",
    })

    assert.is_true(g:match({ ges = "swipe", direction = "east" }))
    assert.is_false(g:match({ ges = "swipe", direction = "west" }))
  end)
end)
