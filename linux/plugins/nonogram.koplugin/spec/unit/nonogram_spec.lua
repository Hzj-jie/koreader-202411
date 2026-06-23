describe("Nonogram board logic unit tests", function()
  local Nonogram
  local plugin
  local board

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    Nonogram = dofile("plugins/nonogram.koplugin/main.lua")
    Nonogram.ui = {
      menu = {
        registerToMainMenu = function() end
      }
    }
    plugin = Nonogram:new()
    board = plugin:getBoard()
  end)

  teardown(function()
    package.unloadAll()
  end)

  local function buildSimplePuzzle()
    return {
      title = "Test Puzzle",
      rows_count = 3,
      cols_count = 3,
      row_hints = { { 1 }, { 2 }, { 3 } },
      col_hints = { { 1 }, { 2 }, { 3 } },
      max_row_hint = 1,
      max_col_hint = 1,
      solution = {
        { true, false, false },
        { true, true, false },
        { true, true, true }
      }
    }
  end

  it("should initialize board state and accept a puzzle", function()
    local puzzle = buildSimplePuzzle()
    board:setCurrentPuzzle(puzzle)

    assert.are.equal(3, board:getRowCount())
    assert.are.equal(3, board:getColCount())
    assert.are.equal("Test Puzzle", board:getPuzzleTitle())
    assert.False(board:isSolved())

    -- Grid should be initialized to -1 (clear)
    local grid = board.user_grid
    for r = 1, 3 do
      for c = 1, 3 do
        assert.are.equal(-1, grid[r][c])
      end
    end
  end)

  it("should apply cell actions and track selections", function()
    local puzzle = buildSimplePuzzle()
    board:setCurrentPuzzle(puzzle)

    -- Select (1, 1) and fill
    board:setSelection(1, 1)
    local r, c = board:getSelection()
    assert.are.equal(1, r)
    assert.are.equal(1, c)

    assert.True(board:applyAction("fill"))
    assert.are.equal(1, board.user_grid[1][1])

    -- Select (1, 2) and mark with X
    board:setSelection(1, 2)
    assert.True(board:applyAction("mark"))
    assert.are.equal(0, board.user_grid[1][2])

    -- Select (1, 1) and clear
    board:setSelection(1, 1)
    assert.True(board:applyAction("clear"))
    assert.are.equal(-1, board.user_grid[1][1])
  end)

  it("should detect solved state correctly", function()
    local puzzle = buildSimplePuzzle()
    board:setCurrentPuzzle(puzzle)

    -- Solve the puzzle according to solution:
    -- (1,1)=true, (2,1)=true, (2,2)=true, (3,1)=true, (3,2)=true, (3,3)=true
    local solution = puzzle.solution
    for r = 1, 3 do
      for c = 1, 3 do
        if solution[r][c] then
          board:setSelection(r, c)
          board:applyAction("fill")
        end
      end
    end

    assert.True(board:isSolved())

    -- If we clear a correct cell, it should not be solved
    board:setSelection(1, 1)
    board:applyAction("clear")
    assert.False(board:isSolved())

    -- If we fill a cell that should be empty, it should not be solved
    board:setSelection(1, 2)
    board:applyAction("fill")
    assert.False(board:isSolved())
  end)
end)
