describe("OverlapGroup", function()
  local OverlapGroup
  local Widget
  local Geom
  local BD

  setup(function()
    require("commonrequire")
    OverlapGroup = require("ui/widget/overlapgroup")
    Widget = require("ui/widget/widget")
    Geom = require("ui/geometry")
    BD = require("ui/bidi")
  end)

  local function createMockWidget(w, h, props)
    local o = {
      dimen = Geom:new({ w = w, h = h }),
    }
    if props then
      for k, v in pairs(props) do
        o[k] = v
      end
    end
    local wgt = Widget:new(o)
    wgt.painted_at = nil
    wgt.paintTo = function(self, bb, x, y)
      self.painted_at = { x = x, y = y }
    end
    return wgt
  end

  it("should calculate bounding box dimensions covering all children", function()
    local w1 = createMockWidget(40, 20)
    local w2 = createMockWidget(60, 50)
    local w3 = createMockWidget(30, 70)

    local og = OverlapGroup:new({
      w1, w2, w3,
    })

    local size = og:getSize()
    assert.are.equal(60, size.w)
    assert.are.equal(70, size.h)
  end)

  it("should paint children with default (left), right, center, and offset alignments", function()
    local w_left = createMockWidget(20, 20)
    local w_right = createMockWidget(20, 20, { overlap_align = "right" })
    local w_center = createMockWidget(20, 20, { overlap_align = "center" })
    local w_offset = createMockWidget(20, 20, { overlap_offset = { 5, 10 } })
    local w_bg = createMockWidget(100, 50)

    local og = OverlapGroup:new({
      w_bg, w_left, w_right, w_center, w_offset,
    })

    og:paintTo({}, 10, 20)
    -- total size is 100x50
    -- w_left (default left): x = 10, y = 20
    assert.are.same({ x = 10, y = 20 }, w_left.painted_at)
    -- w_right: x = 10 + 100 - 20 = 90, y = 20
    assert.are.same({ x = 90, y = 20 }, w_right.painted_at)
    -- w_center: x = 10 + floor((100 - 20)/2) = 10 + 40 = 50, y = 20
    assert.are.same({ x = 50, y = 20 }, w_center.painted_at)
    -- w_offset: x = 10 + 5 = 15, y = 20 + 10 = 30
    assert.are.same({ x = 15, y = 30 }, w_offset.painted_at)
  end)

  it("should mirror alignments and offsets when RTL mirroring is enabled", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w_bg = createMockWidget(100, 50)
    local w_left = createMockWidget(20, 20) -- no overlap_align -> becomes "right"
    local w_right = createMockWidget(20, 20, { overlap_align = "right" }) -- becomes "left"
    local w_center = createMockWidget(20, 20, { overlap_align = "center" }) -- stays "center"
    local w_offset = createMockWidget(20, 20, { overlap_offset = { 10, 5 } }) -- offset flipped: 100 - 20 - 10 = 70

    local og = OverlapGroup:new({
      w_bg, w_left, w_right, w_center, w_offset,
    })

    og:paintTo({}, 0, 0)
    -- w_left became right: x = 0 + 100 - 20 = 80
    assert.are.equal(80, w_left.painted_at.x)
    -- w_right became left: x = 0
    assert.are.equal(0, w_right.painted_at.x)
    -- w_center: x = 40
    assert.are.equal(40, w_center.painted_at.x)
    -- w_offset: x = 70, y = 5
    assert.are.equal(70, w_offset.painted_at.x)
    assert.are.equal(5, w_offset.painted_at.y)

    BD.mirroredUILayout = orig_mirrored
  end)

  it("should not mirror when allow_mirroring is false", function()
    local orig_mirrored = BD.mirroredUILayout
    BD.mirroredUILayout = function() return true end

    local w_bg = createMockWidget(100, 50)
    local w_left = createMockWidget(20, 20)

    local og = OverlapGroup:new({
      allow_mirroring = false,
      w_bg, w_left,
    })

    og:paintTo({}, 0, 0)
    assert.are.equal(0, w_left.painted_at.x)

    BD.mirroredUILayout = orig_mirrored
  end)
end)
