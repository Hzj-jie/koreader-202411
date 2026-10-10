describe("SlidePuzzle BoardWidget module", function()
  local BoardWidget, BD, Blitbuffer, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    Device.isTouchDevice = function()
      return false
    end

    BD = require("ui/bidi")
    Blitbuffer = require("ffi/blitbuffer")
    BoardWidget = require("plugins/slidepuzzle.koplugin/slidepuzzle_board")
  end)

  it("should instantiate BoardWidget and compute metrics", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
      getGrid = function()
        return {
          { 1, 2, 3 },
          { 4, 5, 6 },
          { 7, 8, 0 },
        }
      end,
    }

    local widget = BoardWidget:new({ game = mock_game, max_size = 300 })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()

    assert.is_table(widget)
    assert.are.equal(100, widget.cell)
    assert.are.equal(300, widget.board_size)
  end)

  it("should calculate cell coordinates from touch point", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
    }

    local widget = BoardWidget:new({ game = mock_game, max_size = 300 })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()
    widget.paint_rect = { x = 0, y = 0, w = 300, h = 300 }

    local row, col = widget:_cellFromPoint(50, 150)
    assert.are.equal(2, row)
    assert.are.equal(1, col)
  end)

  it("should handle tap and swipe gestures", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
    }

    local tapped_cell = nil
    local swiped_dir = nil

    local widget = BoardWidget:new({
      game = mock_game,
      max_size = 300,
      onTileTap = function(r, c)
        tapped_cell = { r, c }
      end,
      onSwipeDir = function(dir)
        swiped_dir = dir
      end,
    })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()
    widget.paint_rect = { x = 0, y = 0, w = 300, h = 300 }

    local tap_handled = widget:onTap(nil, { pos = { x = 50, y = 50 } })
    assert.is_true(tap_handled)
    assert.are.same({ 1, 1 }, tapped_cell)

    local swipe_handled = widget:onSwipe(nil, { direction = "west" })
    assert.is_true(swipe_handled)
    assert.are.equal("left", swiped_dir)
  end)

  it("should mirror swipe gestures in RTL mirrored layout", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
    }

    local swiped_dir = nil
    local widget = BoardWidget:new({
      game = mock_game,
      max_size = 300,
      onSwipeDir = function(dir)
        swiped_dir = dir
      end,
    })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()

    local orig_mirrored = BD._mirrored_ui_layout
    BD._mirrored_ui_layout = true
    finally(function()
      BD._mirrored_ui_layout = orig_mirrored
    end)

    -- In mirrored RTL layout, west gesture should map to right move
    widget:onSwipe(nil, { direction = "west" })
    assert.are.equal("right", swiped_dir)

    -- East gesture should map to left move
    widget:onSwipe(nil, { direction = "east" })
    assert.are.equal("left", swiped_dir)

    -- Vertical gestures should remain unchanged
    widget:onSwipe(nil, { direction = "north" })
    assert.are.equal("up", swiped_dir)
    widget:onSwipe(nil, { direction = "south" })
    assert.are.equal("down", swiped_dir)
  end)

  it("should calculate and cap font metrics correctly", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
    }

    local widget = BoardWidget:new({ game = mock_game, max_size = 300 })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()
    -- cell = 100, auto font size = math.max(18, math.floor(100 * 0.45)) = 45
    assert.are.equal(45, widget.number_face.size)

    -- User override under max_px: 60 < 78 (math.floor(100 * 0.78))
    widget:setFontPrefs("cfont", 60)
    assert.are.equal(60, widget.number_face.size)

    -- User override exceeding max_px: 200 > 78, capped to 78
    widget:setFontPrefs("cfont", 200)
    assert.are.equal(78, widget.number_face.size)

    -- Reset to auto
    widget:setFontPrefs(nil, 0)
    assert.are.equal(45, widget.number_face.size)

    -- Small board where cell < MIN_CELL (32)
    local small_game = {
      getSize = function()
        return 10
      end,
    }
    local small_widget = BoardWidget:new({ game = small_game, max_size = 100 })
    small_widget.dimen = { w = 320, h = 320 }
    small_widget:_computeMetrics()
    assert.are.equal(32, small_widget.cell)
    assert.are.equal(320, small_widget.board_size)
    -- max_px = math.max(28, math.floor(32 * 0.78)) = 28
    assert.are.equal(18, small_widget.number_face.size)
  end)

  it("should render tiles and borders properly in paintTo", function()
    local mock_game = {
      getSize = function()
        return 3
      end,
      getGrid = function()
        return {
          { 1, 2, 3 },
          { 4, 5, 6 },
          { 7, 0, 8 },
        }
      end,
    }

    local widget = BoardWidget:new({ game = mock_game, max_size = 300 })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()

    local bb = Blitbuffer.new(300, 300)
    widget:paintTo(bb, 0, 0)
    assert.are.equal(300, widget.paint_rect.w)
    assert.are.equal(300, widget.paint_rect.h)
    bb:free()
  end)
end)
