describe("HorizontalGroup", function()
  local HorizontalGroup
  local Widget
  local Geom
  local BD

  setup(function()
    require("commonrequire")
    HorizontalGroup = require("ui/widget/horizontalgroup")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")
    BD = require("ui/bidi")
  end)

  local function createMockWidget(w, h)
    local wgt = Widget:new({
      dimen = Geom:new({ w = w, h = h }),
    })
    wgt.painted_at = nil
    wgt.paintTo = function(self, bb, x, y)
      self.painted_at = { x = x, y = y }
    end
    return wgt
  end

  it("should calculate size correctly for children", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local w3 = createMockWidget(30, 10)

    local hg = HorizontalGroup:new({
      w1, w2, w3,
    })

    local size = hg:getSize()
    assert.are.equal(130, size.w)
    assert.are.equal(50, size.h)
  end)

  it("should paint children with center alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local hg = HorizontalGroup:new({
      align = "center",
      w1, w2,
    })

    hg:paintTo({}, 10, 100)
    -- size.h = 50
    -- w1: x = 10 + 0 = 10, y = 100 + floor((50 - 20)/2) = 100 + 15 = 115
    assert.are.same({ x = 10, y = 115 }, w1.painted_at)
    -- w2: x = 10 + 40 = 50, y = 100 + floor((50 - 50)/2) = 100
    assert.are.same({ x = 50, y = 100 }, w2.painted_at)
  end)

  it("should paint children with top alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local hg = HorizontalGroup:new({
      align = "top",
      w1, w2,
    })

    hg:paintTo({}, 10, 100)
    assert.are.same({ x = 10, y = 100 }, w1.painted_at)
    assert.are.same({ x = 50, y = 100 }, w2.painted_at)
  end)

  it("should paint children with bottom alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local hg = HorizontalGroup:new({
      align = "bottom",
      w1, w2,
    })

    hg:paintTo({}, 10, 100)
    -- size.h = 50
    -- w1: x = 10, y = 100 + 50 - 20 = 130
    assert.are.same({ x = 10, y = 130 }, w1.painted_at)
    -- w2: x = 50, y = 100 + 50 - 50 = 100
    assert.are.same({ x = 50, y = 100 }, w2.painted_at)
  end)

  it("should handle invalid alignment gracefully", function()
    local w1 = createMockWidget(40, 20)
    local hg = HorizontalGroup:new({
      align = "invalid_align",
      w1,
    })

    hg:paintTo({}, 10, 100)
    assert.is_nil(w1.painted_at)
  end)

  it("should mirror layout when RTL mirroring is enabled", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w1 = createMockWidget(40, 20)
    w1.name = "w1"
    local w2 = createMockWidget(60, 50)
    w2.name = "w2"

    local hg = HorizontalGroup:new({
      align = "top",
      w1, w2,
    })

    local size = hg:getSize()
    assert.are.equal(100, size.w)
    assert.are.equal(50, size.h)
    -- Original order preserved in table
    assert.are.equal("w1", hg[1].name)
    assert.are.equal("w2", hg[2].name)

    hg:paintTo({}, 0, 0)
    -- When mirrored, the widgets were evaluated in reversed order:
    -- first w2 (offset x=0), then w1 (offset x=60)
    assert.are.equal(60, w1.painted_at.x)
    assert.are.equal(0, w2.painted_at.x)

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should not mirror layout when allow_mirroring is false", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)

    local hg = HorizontalGroup:new({
      allow_mirroring = false,
      align = "top",
      w1, w2,
    })

    hg:paintTo({}, 0, 0)
    assert.are.equal(0, w1.painted_at.x)
    assert.are.equal(40, w2.painted_at.x)

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should clear, resetLayout, and free", function()
    local w1 = createMockWidget(40, 20)
    local hg = HorizontalGroup:new({
      w1,
    })

    assert.truthy(hg:getSize())
    assert.truthy(hg._offsets)

    hg:resetLayout()
    assert.is_nil(hg.dimen)
    assert.are.same({}, hg._offsets)

    hg:clear()
    assert.are.equal(0, #hg)

    hg:free()
    assert.is_nil(hg.dimen)
  end)
end)
