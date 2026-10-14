local Nonogram

describe("Nonogram plugin", function()
  local mock_ui

  setup(function()
    require("commonrequire")
    Nonogram = require("plugins/nonogram.koplugin/main")
  end)

  before_each(function()
    mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
  end)

  describe("Board logic and puzzle management", function()
    it("initializes puzzle board and handles cell actions", function()
      local nonogram = Nonogram:new({
        ui = mock_ui,
        path = "plugins/nonogram.koplugin",
      })

      local board = nonogram:getBoard()
      assert.is_table(board)

      local puzzle = {
        title = "Test 2x2",
        rows_count = 2,
        cols_count = 2,
        solution = {
          { true, false },
          { false, true },
        },
        row_hints = { { 1 }, { 1 } },
        col_hints = { { 1 }, { 1 } },
        max_row_hint_count = 1,
        max_col_hint_count = 1,
      }
      board:setCurrentPuzzle(puzzle)
      assert.are.equal(2, board:getRowCount())
      assert.are.equal(2, board:getColCount())
      assert.is_false(board:isSolved())

      -- Apply actions
      board:setSelection(1, 1)
      board:applyAction("fill")
      assert.are.equal(1, board.user_grid[1][1])

      board:setSelection(2, 2)
      board:applyAction("fill")
      assert.are.equal(1, board.user_grid[2][2])

      assert.is_true(board:isSolved())
    end)

    it("serializes and restores board progress", function()
      local nonogram = Nonogram:new({
        ui = mock_ui,
        path = "plugins/nonogram.koplugin",
      })
      local board = nonogram:getBoard()
      local puzzle = {
        title = "Test 2x2",
        rows_count = 2,
        cols_count = 2,
        solution = {
          { true, false },
          { false, true },
        },
        row_hints = { { 1 }, { 1 } },
        col_hints = { { 1 }, { 1 } },
        max_row_hint_count = 1,
        max_col_hint_count = 1,
      }
      board:setCurrentPuzzle(puzzle)
      board:setSelection(1, 1)
      board:applyAction("fill")

      local state = board:serialize()
      assert.is_table(state)
      assert.are.equal(1, state.user_grid[1][1])

      board:resetProgress()
      assert.are.equal(-1, board.user_grid[1][1])

      assert.is_true(board:load(state))
      assert.are.equal(1, board.user_grid[1][1])
    end)
  end)

  describe("Defect verifications", function()
    it(
      "revealHint clears conflict indicators when resolving an incorrect cell",
      function()
        local nonogram = Nonogram:new({
          ui = mock_ui,
          path = "plugins/nonogram.koplugin",
        })
        local board = nonogram:getBoard()
        local puzzle = {
          title = "Test 2x2",
          rows_count = 2,
          cols_count = 2,
          solution = {
            { true, false },
            { false, true },
          },
          row_hints = { { 1 }, { 1 } },
          col_hints = { { 1 }, { 1 } },
          max_row_hint_count = 1,
          max_col_hint_count = 1,
        }
        board:setCurrentPuzzle(puzzle)

        -- Fill correct cells and intentionally fill an incorrect cell (1, 2)
        board.user_grid[1][1] = 1
        board.user_grid[2][2] = 1
        board.user_grid[1][2] = 1
        board:checkProgress()
        assert.is_true(board:areConflictsVisible())

        -- revealHint should clear cell (1, 2) to -1 and clear conflict indicators
        local ok, msg = board:revealHint()
        assert.is_true(ok)
        assert.is_string(msg)
        assert.are.equal(-1, board.user_grid[1][2])

        -- Conflict indicator should be reset after correcting the mistake
        assert.is_false(
          board:areConflictsVisible(),
          "conflict_visible should be false after correcting the only mistake"
        )
      end
    )

    it(
      "revealHint fills earlier missing correct cell before clearing later incorrect cell",
      function()
        local nonogram = Nonogram:new({
          ui = mock_ui,
          path = "plugins/nonogram.koplugin",
        })
        local board = nonogram:getBoard()
        local puzzle = {
          title = "Test 2x2 Order",
          rows_count = 2,
          cols_count = 2,
          solution = {
            { true, false },
            { false, true },
          },
          row_hints = { { 1 }, { 1 } },
          col_hints = { { 1 }, { 1 } },
          max_row_hint_count = 1,
          max_col_hint_count = 1,
        }
        board:setCurrentPuzzle(puzzle)
        board:resetProgress()

        -- Cell (1, 1) is solution=true, user_grid=-1 (earlier missing correct cell)
        -- Cell (2, 1) is solution=false, user_grid=1 (later incorrectly filled cell)
        board.user_grid[2][1] = 1

        -- In row-major order, cell (1, 1) should be filled first
        local ok, msg = board:revealHint()
        assert.is_true(ok)
        assert.are.equal(1, board.user_grid[1][1])
        assert.are.equal(1, board.user_grid[2][1])

        -- Next hint in row-major order should clear cell (2, 1)
        ok, msg = board:revealHint()
        assert.is_true(ok)
        assert.are.equal(-1, board.user_grid[2][1])
      end
    )

    it(
      "NonogramBoardWidget:getCellFromPoint maps right and bottom grid boundary points",
      function()
        local nonogram = Nonogram:new({
          ui = mock_ui,
          path = "plugins/nonogram.koplugin",
        })
        local board = nonogram:getBoard()
        local puzzle = {
          title = "Test 3x3",
          rows_count = 3,
          cols_count = 3,
          solution = {
            { true, false, false },
            { false, true, false },
            { false, false, true },
          },
          row_hints = { { 1 }, { 1 }, { 1 } },
          col_hints = { { 1 }, { 1 }, { 1 } },
          max_row_hint_count = 1,
          max_col_hint_count = 1,
        }
        board:setCurrentPuzzle(puzzle)

        nonogram:showGame()
        local widget = nonogram.screen.board_widget
        assert.is_table(widget)
        widget:updateMetrics()

        local cell = widget.cell_size
        local cols = board:getColCount()
        -- Point on the rightmost boundary pixel of the grid
        local x = widget.grid_origin_x + cols * cell
        local y = widget.grid_origin_y + math.floor(cell / 2)

        local row, col = widget:getCellFromPoint(x, y)
        assert.are.equal(1, row)
        assert.are.equal(cols, col)

        local rows = board:getRowCount()
        -- Point on the bottom boundary pixel of the grid
        local bx = widget.grid_origin_x + math.floor(cell / 2)
        local by = widget.grid_origin_y + rows * cell

        local brow, bcol = widget:getCellFromPoint(bx, by)
        assert.are.equal(rows, brow)
        assert.are.equal(1, bcol)
      end
    )
  end)
end)
