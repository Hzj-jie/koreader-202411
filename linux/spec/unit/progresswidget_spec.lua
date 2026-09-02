describe("ProgressWidget", function()
  local ProgressWidget
  local BD
  local Blitbuffer
  local Device
  local Geom

  setup(function()
    require("commonrequire")
    ProgressWidget = require("ui/widget/progresswidget")
    BD = require("ui/bidi")
    Blitbuffer = require("ffi/blitbuffer")
    Device = require("device")
    Geom = require("ui/geometry")
  end)

  local function createMockBB()
    local operations = {}
    return setmetatable({
      paintRect = function(self, x, y, w, h, color)
        table.insert(operations, { op = "paintRect", x = x, y = y, w = w, h = h, color = color })
      end,
      paintRoundedRect = function(self, x, y, w, h, color, radius)
        table.insert(operations, { op = "paintRoundedRect", x = x, y = y, w = w, h = h, color = color, radius = radius })
      end,
      paintBorder = function(self, x, y, w, h, size, color, radius)
        table.insert(operations, { op = "paintBorder", x = x, y = y, w = w, h = h, size = size, color = color, radius = radius })
      end,
      blitFrom = function(self, src, ...)
        table.insert(operations, { op = "blitFrom", src = src })
      end,
      getOperations = function()
        return operations
      end,
    }, {
      __index = function()
        return function() end
      end,
    })
  end

  describe("initialization and marker rendering", function()
    it("should instantiate with default values", function()
      local pw = ProgressWidget:new({
        width = 200,
        height = 20,
        percentage = 0.5,
      })

      assert.are.equal(200, pw.width)
      assert.are.equal(20, pw.height)
      assert.are.equal(0.5, pw.percentage)
      assert.is_false(pw.initial_pos_marker)
    end)

    it("should initialize initial_pos_marker and icon based on height threshold", function()
      -- Small height (<= 12) -> position.marker.top
      local pw_small = ProgressWidget:new({
        width = 200,
        height = 10,
        percentage = 0.4,
        initial_pos_marker = true,
      })
      assert.truthy(pw_small.initial_pos_icon)
      assert.are.equal(0.4, pw_small.initial_percentage)

      -- Large height (> 12) -> position.marker
      local pw_large = ProgressWidget:new({
        width = 200,
        height = 30,
        percentage = 0.6,
        initial_percentage = 0.3,
        initial_pos_marker = true,
      })
      assert.truthy(pw_large.initial_pos_icon)
      assert.are.equal(0.3, pw_large.initial_percentage)

      -- Free
      pw_small:free()
      pw_large:free()
    end)

    it("should handle renderMarkerIcon edge cases", function()
      local pw = ProgressWidget:new({
        width = 200,
        initial_pos_marker = false,
      })
      pw:renderMarkerIcon()
      assert.is_nil(pw.initial_pos_icon)

      pw.initial_pos_marker = true
      pw.height = nil
      pw:renderMarkerIcon()
      assert.is_nil(pw.initial_pos_icon)

      pw.height = 20
      pw:renderMarkerIcon()
      assert.truthy(pw.initial_pos_icon)

      -- Re-render should free previous icon
      pw:renderMarkerIcon()
      assert.truthy(pw.initial_pos_icon)

      pw:free()
    end)
  end)

  describe("paintTo rendering", function()
    it("should early return when dimensions are 0", function()
      local pw = ProgressWidget:new({
        width = 0,
        height = 0,
        percentage = 0.5,
      })
      local bb = createMockBB()
      pw:paintTo(bb, 0, 0)
      assert.are.equal(0, #bb.getOperations())
    end)

    it("should paint with rounded border when radius > 0", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        radius = 4,
        margin_h = 2,
        margin_v = 1,
        bordersize = 1,
      })
      local bb = createMockBB()
      pw:paintTo(bb, 10, 10)

      local ops = bb.getOperations()
      assert.is_true(#ops >= 3)
      assert.are.equal("paintRoundedRect", ops[1].op)
      assert.are.equal("paintBorder", ops[2].op)
      assert.are.equal("paintRect", ops[3].op) -- fill bar
    end)

    it("should paint with rectangular border when radius == 0", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        radius = 0,
        margin_h = 2,
        margin_v = 1,
        bordersize = 1,
      })
      local bb = createMockBB()
      pw:paintTo(bb, 10, 10)

      local ops = bb.getOperations()
      assert.is_true(#ops >= 3)
      assert.are.equal("paintRect", ops[1].op) -- border
      assert.are.equal("paintRect", ops[2].op) -- bg
      assert.are.equal("paintRect", ops[3].op) -- fill
    end)

    it("should paint alt pages flow markers", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        radius = 0,
        last = 100,
        alt = { { 10, 20 }, { 50, 10 } },
      })
      local bb = createMockBB()
      pw:paintTo(bb, 0, 0)

      local ops = bb.getOperations()
      local alt_ops = 0
      for _, op in ipairs(ops) do
        if op.color == pw.altcolor then
          alt_ops = alt_ops + 1
        end
      end
      assert.are.equal(2, alt_ops)
    end)

    it("should paint ticks", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        radius = 0,
        last = 100,
        ticks = { 25, 50, 75 },
      })
      local bb = createMockBB()
      pw:paintTo(bb, 0, 0)

      local ops = bb.getOperations()
      local tick_ops = 0
      for _, op in ipairs(ops) do
        if op.w == pw.tick_width then
          tick_ops = tick_ops + 1
        end
      end
      assert.are.equal(3, tick_ops)
    end)

    it("should paint fill_from_right and mirrored UI layout", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        fill_from_right = true,
        last = 100,
        ticks = { 25 },
        alt = { { 10, 10 } },
      })
      local bb = createMockBB()
      pw:paintTo(bb, 0, 0)
      assert.is_true(#bb.getOperations() > 0)

      -- Mirrored UI layout
      local orig_mirrored = BD.mirroredUILayout
      BD.mirroredUILayout = function()
        return true
      end

      local pw_mirrored = ProgressWidget:new({
        width = 100,
        height = 20,
        percentage = 0.5,
        fill_from_right = false,
        last = 100,
        ticks = { 25 },
        alt = { { 10, 10 } },
      })
      local bb_mirrored = createMockBB()
      pw_mirrored:paintTo(bb_mirrored, 0, 0)
      assert.is_true(#bb_mirrored.getOperations() > 0)

      BD.mirroredUILayout = orig_mirrored
    end)

    it("should paint initial_pos_marker on top of fill bar", function()
      -- Small height
      local pw_small = ProgressWidget:new({
        width = 100,
        height = 10,
        percentage = 0.5,
        initial_pos_marker = true,
      })
      local bb1 = createMockBB()
      pw_small:paintTo(bb1, 0, 0)
      assert.is_true(#bb1.getOperations() > 0)
      pw_small:free()

      -- Large height
      local pw_large = ProgressWidget:new({
        width = 100,
        height = 24,
        percentage = 0.5,
        initial_pos_marker = true,
      })
      local bb2 = createMockBB()
      pw_large:paintTo(bb2, 0, 0)
      assert.is_true(#bb2.getOperations() > 0)
      pw_large:free()
    end)
  end)

  describe("setPercentage and getPercentageFromPosition", function()
    it("should update percentage and set initial_percentage if marker enabled", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
        initial_pos_marker = true,
      })
      assert.is_nil(pw.percentage)
      assert.is_nil(pw.initial_percentage)

      pw:setPercentage(0.75)
      assert.are.equal(0.75, pw.percentage)
      assert.are.equal(0.75, pw.initial_percentage)

      -- Changing percentage again does not overwrite initial_percentage
      pw:setPercentage(0.85)
      assert.are.equal(0.85, pw.percentage)
      assert.are.equal(0.75, pw.initial_percentage)
      pw:free()
    end)

    it("should calculate percentage from position coordinate", function()
      local pw = ProgressWidget:new({
        width = 106,
        height = 20,
        margin_h = 3,
      })
      pw.dimen = Geom:new({ x = 10, y = 10, w = 106, h = 20 })

      -- Inner width = 106 - 2*3 = 100
      -- Inside position at x = 10 + 3 + 50 = 63 -> 50 / 100 = 0.5
      local pct = pw:getPercentageFromPosition({ x = 63, y = 15 })
      assert.are.equal(0.5, pct)

      -- Nil or missing x
      assert.is_nil(pw:getPercentageFromPosition(nil))
      assert.is_nil(pw:getPercentageFromPosition({ y = 15 }))

      -- Out of bounds left (< 10 + 3 = 13)
      assert.is_nil(pw:getPercentageFromPosition({ x = 10, y = 15 }))

      -- Out of bounds right (> 10 + 3 + 100 = 113)
      assert.is_nil(pw:getPercentageFromPosition({ x = 120, y = 15 }))

      -- Mirrored UI layout
      local orig_mirrored = BD.mirroredUILayout
      BD.mirroredUILayout = function()
        return true
      end

      -- In mirrored mode, x = 63 -> width - (63 - 10 - 3) = 100 - 50 = 50 -> 0.5
      -- at x = 38 -> (38 - 13) = 25 -> mirrored: 100 - 25 = 75 -> 0.75
      local pct_mirrored = pw:getPercentageFromPosition({ x = 38, y = 15 })
      assert.are.equal(0.75, pct_mirrored)

      BD.mirroredUILayout = orig_mirrored
    end)
  end)

  describe("setHeight and updateStyle", function()
    it("should adjust margins and bordersize on setHeight", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 30,
        margin_v = 4,
        bordersize = 2,
        initial_pos_marker = true,
      })

      pw:setHeight(6)
      assert.is_true(pw.margin_v >= 1)
      assert.is_true(pw.bordersize >= 1)
      assert.truthy(pw.initial_pos_icon)
      pw:free()
    end)

    it("should updateStyle for thick and thin styles", function()
      local pw = ProgressWidget:new({
        width = 100,
        height = 20,
      })

      -- Thin style
      pw:updateStyle(false, 10)
      assert.are.equal(0, pw.margin_h)
      assert.are.equal(0, pw.margin_v)
      assert.are.equal(0, pw.bordersize)
      assert.are.equal(0, pw.radius)
      assert.are.equal(Blitbuffer.COLOR_GRAY, pw.bgcolor)
      assert.are.equal(Blitbuffer.COLOR_GRAY_5, pw.fillcolor)
      assert.is_nil(pw.ticks)

      -- Thick style
      pw:updateStyle(true, 25)
      assert.is_true(pw.margin_h > 0)
      assert.is_true(pw.radius > 0)
      assert.are.equal(Blitbuffer.COLOR_WHITE, pw.bgcolor)
      assert.are.equal(Blitbuffer.COLOR_DARK_GRAY, pw.fillcolor)
    end)
  end)
end)
