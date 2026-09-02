describe("VerticalGroup", function()
  local VerticalGroup
  local Widget
  local Geom
  local BD

  setup(function()
    require("commonrequire")
    VerticalGroup = require("ui/widget/verticalgroup")
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

    local vg = VerticalGroup:new({
      w1, w2, w3,
    })

    local size = vg:getSize()
    assert.are.equal(60, size.w)
    assert.are.equal(80, size.h)
  end)

  it("should paint children with center alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local vg = VerticalGroup:new({
      align = "center",
      w1, w2,
    })

    vg:paintTo({}, 10, 100)
    -- size.w = 60
    -- w1: x = 10 + floor((60 - 40)/2) = 10 + 10 = 20, y = 100 + 0 = 100
    assert.are.same({ x = 20, y = 100 }, w1.painted_at)
    -- w2: x = 10 + floor((60 - 60)/2) = 10, y = 100 + 20 = 120
    assert.are.same({ x = 10, y = 120 }, w2.painted_at)
  end)

  it("should paint children with left alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local vg = VerticalGroup:new({
      align = "left",
      w1, w2,
    })

    vg:paintTo({}, 10, 100)
    assert.are.same({ x = 10, y = 100 }, w1.painted_at)
    assert.are.same({ x = 10, y = 120 }, w2.painted_at)
  end)

  it("should paint children with right alignment", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local vg = VerticalGroup:new({
      align = "right",
      w1, w2,
    })

    vg:paintTo({}, 10, 100)
    -- size.w = 60
    -- w1: x = 10 + 60 - 40 = 30, y = 100
    assert.are.same({ x = 30, y = 100 }, w1.painted_at)
    -- w2: x = 10 + 60 - 60 = 10, y = 120
    assert.are.same({ x = 10, y = 120 }, w2.painted_at)
  end)

  it("should swap left and right alignment when RTL mirroring is enabled", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w1 = createMockWidget(40, 20)
    local vg_left = VerticalGroup:new({
      align = "left",
      w1,
    })
    vg_left:paintTo({}, 0, 0)
    -- size.w = 40, align swapped to right: x = 0 + 40 - 40 = 0
    local w2 = createMockWidget(40, 20)
    local w3 = createMockWidget(60, 20)
    local vg_left_multi = VerticalGroup:new({
      align = "left",
      w2, w3,
    })
    vg_left_multi:paintTo({}, 0, 0)
    -- size.w = 60, align swapped to right: w2 x = 0 + 60 - 40 = 20
    assert.are.equal(20, w2.painted_at.x)

    local w4 = createMockWidget(40, 20)
    local vg_right = VerticalGroup:new({
      align = "right",
      w4,
    })
    vg_right:paintTo({}, 15, 0)
    -- align swapped to left: w4 x = 15
    assert.are.equal(15, w4.painted_at.x)

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should not swap alignment when allow_mirroring is false", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 20)
    local vg = VerticalGroup:new({
      allow_mirroring = false,
      align = "left",
      w1, w2,
    })
    vg:paintTo({}, 10, 0)
    assert.are.equal(10, w1.painted_at.x)

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should clear, resetLayout, and free", function()
    local w1 = createMockWidget(40, 20)
    local vg = VerticalGroup:new({
      w1,
    })

    assert.truthy(vg:getSize())
    assert.truthy(vg._offsets)

    vg:resetLayout()
    assert.is_nil(vg.dimen)
    assert.are.same({}, vg._offsets)

    vg:clear()
    assert.are.equal(0, #vg)

    vg:free()
    assert.is_nil(vg.dimen)
  end)
end)
