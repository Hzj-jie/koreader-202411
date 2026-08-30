describe("Nonogram board and plugin unit tests", function()
  local Nonogram, Blitbuffer, UIManager, Geom, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Blitbuffer = require("ffi/blitbuffer")
    UIManager = require("ui/uimanager")
    Geom = require("ui/geometry")
    Device = require("device")
    Nonogram = dofile("plugins/nonogram.koplugin/main.lua")
  end)

  after_each(function()
    UIManager._task_queue = {}
    UIManager._next_tick_tasks = {}
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
        { true, true, true },
      },
    }
  end

  describe("NonogramBoard logic", function()
    it("should initialize board state, generate random puzzle, and serialize/load", function()
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local plugin = Nonogram:new({ ui = mock_ui })
      local board = plugin:getBoard()

      local puzzle = buildSimplePuzzle()
      board:setCurrentPuzzle(puzzle)

      assert.are_equal(3, board:getRowCount())
      assert.are_equal(3, board:getColCount())
      assert.are_equal("Test Puzzle", board:getPuzzleTitle())
      assert.is_table(board:getRowHints(1))
      assert.is_table(board:getColHints(1))
      assert.are_equal(1, board:getMaxRowHintCount())
      assert.are_equal(1, board:getMaxColHintCount())
      assert.is_false(board:isSolved())
      assert.is_false(board:isShowingSolution())

      board:toggleSolution()
      assert.is_true(board:isShowingSolution())
      board:toggleSolution()

      -- Check serialization and loading
      local state = board:serialize()
      assert.is_table(state)

      local loaded = board:load(state)
      assert.is_true(loaded)
      assert.is_false(board:load(nil))
      assert.is_false(board:load({}))

      -- Random puzzle generation
      local rand_puz = board:generateRandomPuzzle(5, 5, 0.4)
      assert.is_table(rand_puz)
      assert.are_equal(5, board:getRowCount())
      assert.are_equal(5, board:getColCount())
    end)

    it("should apply actions, check progress, and reveal hints", function()
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local plugin = Nonogram:new({ ui = mock_ui })
      local board = plugin:getBoard()
      local puzzle = buildSimplePuzzle()
      board:setCurrentPuzzle(puzzle)

      -- Select (1, 1) and fill
      board:setSelection(1, 1)
      local r, c = board:getSelection()
      assert.are_equal(1, r)
      assert.are_equal(1, c)

      assert.is_true(board:applyAction("fill"))
      assert.are_equal(1, board.user_grid[1][1])

      -- Select (1, 2) and mark with X
      board:setSelection(1, 2)
      assert.is_true(board:applyAction("mark"))
      assert.are_equal(0, board.user_grid[1][2])

      -- Select (1, 1) and clear
      board:setSelection(1, 1)
      assert.is_true(board:applyAction("clear"))
      assert.are_equal(-1, board.user_grid[1][1])

      -- Invalid action
      local ok, err = board:applyAction("invalid_action")
      assert.is_false(ok)
      assert.is_string(err)

      -- Test revealHint
      local hint_ok, hint_msg = board:revealHint()
      assert.is_true(hint_ok)
      assert.is_string(hint_msg)

      -- Test checkProgress
      local prog = board:checkProgress()
      assert.is_table(prog)
      assert.is_boolean(prog.solved)

      -- Check row/col satisfaction
      assert.is_boolean(board:isRowSatisfied(1))
      assert.is_boolean(board:isColSatisfied(1))
      assert.is_boolean(board:isCellConflict(1, 1))

      -- Restart puzzle
      board:restartPuzzle()
      assert.are_equal(-1, board.user_grid[1][1])
    end)

    it("should detect solved state when puzzle matches solution", function()
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local plugin = Nonogram:new({ ui = mock_ui })
      local board = plugin:getBoard()
      local puzzle = buildSimplePuzzle()
      board:setCurrentPuzzle(puzzle)

      local solution = puzzle.solution
      for r = 1, 3 do
        for c = 1, 3 do
          if solution[r][c] then
            board:setSelection(r, c)
            board:applyAction("fill")
          end
        end
      end

      assert.is_true(board:isSolved())
      local prog = board:checkProgress()
      assert.is_true(prog.solved)
    end)
  end)

  describe("NonogramBoardWidget and NonogramScreen UI", function()
    it("should initialize screen, handle actions, buttons, and paintTo", function()
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local plugin = Nonogram:new({ ui = mock_ui })
      plugin:init()

      -- addToMainMenu
      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.nonogram)
      assert.is_function(menu_items.nonogram.callback)

      -- showGame
      plugin:showGame()
      assert.is_table(plugin.screen)
      local screen = plugin.screen

      -- Test screen action buttons and setters
      screen:setActiveAction("mark")
      assert.are_equal("mark", screen.active_action)
      screen:setActiveAction("fill")
      assert.are_equal("fill", screen.active_action)

      screen:onCellActivated(1, 1)
      screen:onAction("fill")
      screen:onHint()
      screen:onCheck()
      screen:toggleSolution()
      screen:toggleSolution()
      screen:onRestart()
      screen:onNewGame()

      -- Test board widget tap
      local board_widget = screen.board_widget
      assert.is_table(board_widget)
      board_widget:setMaxDimensions(500, 500)
      local row, col = board_widget:getCellFromPoint(board_widget.grid_origin_x + 10, board_widget.grid_origin_y + 10)
      if row and col then
        assert.is_number(row)
        assert.is_number(col)
      end

      board_widget:onTap(nil, { pos = { x = board_widget.grid_origin_x + 10, y = board_widget.grid_origin_y + 10 } })

      -- Test paintTo on a real Blitbuffer
      local bb = Blitbuffer.new(600, 800)
      screen:paintTo(bb, 0, 0)
      bb:free()

      -- Close screen
      screen:onClose()
      assert.is_nil(plugin.screen)
    end)
  end)
end)
