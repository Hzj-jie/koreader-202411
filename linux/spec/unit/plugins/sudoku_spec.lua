describe("Sudoku plugin", function()
  local Sudoku
  local UIManager, Screen, Blitbuffer

  setup(function()
    require("commonrequire")
    Sudoku = require("plugins/sudoku.koplugin/main")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    Blitbuffer = require("ffi/blitbuffer")
  end)

  local function createMockSudoku()
    local sudoku = Sudoku:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    sudoku.settings = {
      data = {},
      read = function(self, key)
        return self.data[key]
      end,
      save = function(self, key, val)
        self.data[key] = val
      end,
      flush = function() end,
    }
    return sudoku
  end

  it("should initialize Sudoku plugin and register to main menu", function()
    local sudoku = createMockSudoku()
    sudoku:init()
    local items = {}
    sudoku:addToMainMenu(items)
    assert.is_table(items.sudoku)
    assert.is_function(items.sudoku.callback)
  end)

  it("should generate board and manage working values and givens", function()
    local sudoku = createMockSudoku()
    local board = sudoku:getBoard()
    board:generate("easy")
    assert.are.equal("easy", board.difficulty)

    local given_count = 0
    local empty_count = 0
    for r = 1, 9 do
      for c = 1, 9 do
        if board:isGiven(r, c) then
          given_count = given_count + 1
          assert.are.equal(board.puzzle[r][c], board:getWorkingValue(r, c))
          local val, is_given = board:getDisplayValue(r, c)
          assert.are.equal(board.puzzle[r][c], val)
          assert.is_true(is_given)
        else
          empty_count = empty_count + 1
        end
      end
    end
    assert.is_true(given_count > 0)
    assert.is_true(empty_count > 0)
    assert.are.equal(81, given_count + empty_count)
    assert.are.equal(empty_count, board:getRemainingCells())
  end)

  it("should handle selection, values, conflicts, and undo on board", function()
    local sudoku = createMockSudoku()
    local board = sudoku:getBoard()
    board:generate("easy")

    -- Find first non-given cell
    local target_r, target_c
    for r = 1, 9 do
      for c = 1, 9 do
        if not board:isGiven(r, c) then
          target_r, target_c = r, c
          break
        end
      end
      if target_r then
        break
      end
    end

    board:setSelection(target_r, target_c)
    local sel_r, sel_c = board:getSelection()
    assert.are.equal(target_r, sel_r)
    assert.are.equal(target_c, sel_c)

    -- Set value
    assert.is_true(board:setValue(5))
    assert.are.equal(5, board.user[target_r][target_c])
    assert.is_true(board:canUndo())

    -- Clear selection
    assert.is_true(board:clearSelection())
    assert.are.equal(0, board.user[target_r][target_c])

    -- Undo clear
    assert.is_true(board:undo())
    assert.are.equal(5, board.user[target_r][target_c])

    -- Undo set
    assert.is_true(board:undo())
    assert.are.equal(0, board.user[target_r][target_c])
    assert.is_false(board:canUndo())
  end)

  it("should handle pencil notes and wrong marks", function()
    local sudoku = createMockSudoku()
    local board = sudoku:getBoard()
    board:generate("easy")

    local target_r, target_c
    for r = 1, 9 do
      for c = 1, 9 do
        if not board:isGiven(r, c) then
          target_r, target_c = r, c
          break
        end
      end
      if target_r then
        break
      end
    end
    board:setSelection(target_r, target_c)

    -- Toggle note
    board:toggleNoteDigit(3)
    local notes = board:getCellNotes(target_r, target_c)
    assert.is_not_nil(notes)
    assert.is_true(notes[3])

    -- Undo note
    assert.is_true(board:undo())
    assert.is_nil(board:getCellNotes(target_r, target_c))

    -- Set incorrect value and update wrong marks
    local correct_val = board.solution[target_r][target_c]
    local wrong_val = (correct_val % 9) + 1
    board:setValue(wrong_val)
    board:updateWrongMarks()
    assert.is_true(board:hasWrongMark(target_r, target_c))

    board:clearWrongMarks()
    assert.is_false(board:hasWrongMark(target_r, target_c))
  end)

  it("should serialize and load board state", function()
    local sudoku = createMockSudoku()
    local board = sudoku:getBoard()
    board:generate("medium")

    local state = board:serialize()
    assert.is_table(state)
    assert.are.equal("medium", state.difficulty)

    local new_board = sudoku.board
    sudoku.board = nil
    local loaded_board = sudoku:getBoard()
    assert.is_true(loaded_board:load(state))
    assert.are.equal("medium", loaded_board.difficulty)
  end)

  it("should manage SudokuScreen lifecycle and keypad callbacks", function()
    local sudoku = createMockSudoku()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local shown_widget
    UIManager.show = function(self, widget)
      shown_widget = widget
    end
    UIManager.close = function() end

    sudoku:showGame()
    assert.is_not_nil(sudoku.screen)
    assert.are.equal(sudoku.screen, shown_widget)

    local screen = sudoku.screen
    screen:toggleNoteMode()
    assert.is_true(screen.note_mode)
    screen:toggleNoteMode()
    assert.is_false(screen.note_mode)

    screen:toggleSolution()
    assert.is_true(screen.board:isShowingSolution())
    screen:toggleSolution()
    assert.is_false(screen.board:isShowingSolution())

    screen:startNewGame()
    screen:checkProgress()

    -- Test board widget onTap and paintTo
    local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight())
    screen:paintTo(bb, 0, 0)
    screen.board_widget:paintTo(bb, 0, 0)

    local pt = {
      x = screen.board_widget.dimen.x + 10,
      y = screen.board_widget.dimen.y + 10,
    }
    screen.board_widget:onTap(nil, pt)

    sudoku:onScreenClosed()
    assert.is_nil(sudoku.screen)

    UIManager.show = orig_show
    UIManager.close = orig_close
  end)

  it(
    "should support undo when erasing pencil notes on an empty cell [exposes production bug in SudokuScreen:eraseDigit()]",
    function()
      local sudoku = createMockSudoku()
      local orig_show = UIManager.show
      UIManager.show = function() end
      sudoku:showGame()
      local screen = sudoku.screen

      -- Find empty cell
      local target_r, target_c
      for r = 1, 9 do
        for c = 1, 9 do
          if
            not screen.board:isGiven(r, c) and screen.board.user[r][c] == 0
          then
            target_r, target_c = r, c
            break
          end
        end
        if target_r then
          break
        end
      end
      screen.board:setSelection(target_r, target_c)

      -- Add pencil note 5 on empty cell
      screen.board:toggleNoteDigit(5)
      assert.is_not_nil(screen.board:getCellNotes(target_r, target_c))
      assert.is_true(screen.board:getCellNotes(target_r, target_c)[5])

      -- Erase digit on cell that only has notes
      screen:eraseDigit()
      assert.is_nil(screen.board:getCellNotes(target_r, target_c))

      -- Erasing notes should be undoable
      assert.is_true(screen.board:canUndo())
      assert.is_true(screen.board:undo())
      local notes = screen.board:getCellNotes(target_r, target_c)
      assert.is_not_nil(notes)
      assert.is_true(notes[5])

      UIManager.show = orig_show
    end
  )

  it(
    "should preserve pencil notes when eraseDigit is called while revealing solution [exposes production bug in SudokuScreen:eraseDigit()]",
    function()
      local sudoku = createMockSudoku()
      local orig_show = UIManager.show
      UIManager.show = function() end
      sudoku:showGame()
      local screen = sudoku.screen

      local target_r, target_c
      for r = 1, 9 do
        for c = 1, 9 do
          if not screen.board:isGiven(r, c) then
            target_r, target_c = r, c
            break
          end
        end
        if target_r then
          break
        end
      end
      screen.board:setSelection(target_r, target_c)

      -- Add pencil note
      screen.board:toggleNoteDigit(7)
      assert.is_not_nil(screen.board:getCellNotes(target_r, target_c))

      -- Reveal solution
      screen.board:toggleSolution()
      assert.is_true(screen.board:isShowingSolution())

      -- Calling eraseDigit while solution is revealed should NOT wipe user's notes
      screen:eraseDigit()
      assert.is_not_nil(screen.board:getCellNotes(target_r, target_c))
      assert.is_true(screen.board:getCellNotes(target_r, target_c)[7])

      UIManager.show = orig_show
    end
  )
end)
