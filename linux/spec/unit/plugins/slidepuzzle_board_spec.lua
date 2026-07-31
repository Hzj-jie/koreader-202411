describe("SlidePuzzle BoardWidget module", function()
  local BoardWidget, Font, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Device = require("device")
    Device.isTouchDevice = function() return false end

    Font = require("ui/font")
    Font.getFace = function(self, name, size)
      return { name = name, size = size }
    end

    BoardWidget = require("plugins/slidepuzzle.koplugin/slidepuzzle_board")
  end)

  it("should instantiate BoardWidget and compute metrics", function()
    local mock_game = {
      getSize = function() return 3 end,
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
      getSize = function() return 3 end,
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
      getSize = function() return 3 end,
    }

    local tapped_cell = nil
    local swiped_dir = nil

    local widget = BoardWidget:new({
      game = mock_game,
      max_size = 300,
      onTileTap = function(r, c) tapped_cell = { r, c } end,
      onSwipeDir = function(dir) swiped_dir = dir end,
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

  it("should update font preferences and max size", function()
    local mock_game = {
      getSize = function() return 3 end,
    }

    local widget = BoardWidget:new({ game = mock_game, max_size = 300 })
    widget.dimen = { w = 300, h = 300 }
    widget:_computeMetrics()

    widget:setFontPrefs("cfont", 24)
    assert.are.equal(24, widget.font_size_override)

    widget:setMaxSize(400)
    assert.are.equal(399, widget.board_size)
  end)
end)
