describe("Sudoku plugin unit tests", function()
  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  teardown(function()
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  it("should generate a sudoku board and allow basic moves", function()
    local class = dofile("plugins/sudoku.koplugin/main.lua")
    local mock_ui = {
      menu = {
        registerToMainMenu = function() end,
      },
    }
    local Sudoku = class:new({ ui = mock_ui })
    local board = Sudoku:getBoard()
    assert.is_not_nil(board)

    -- Let's test the board generation
    board:generate("easy")
    assert.are.equal("easy", board.difficulty)

    -- There must be some numbers given
    local given_count = 0
    for r = 1, 9 do
      for c = 1, 9 do
        if board:isGiven(r, c) then
          given_count = given_count + 1
        end
      end
    end
    assert.True(given_count > 0)
    assert.True(given_count < 81)

    -- Select a non-given cell and check we can set a value
    local selected_r, selected_c
    for r = 1, 9 do
      for c = 1, 9 do
        if not board:isGiven(r, c) then
          selected_r = r
          selected_c = c
          break
        end
      end
      if selected_r then
        break
      end
    end

    board:setSelection(selected_r, selected_c)
    local r, c = board:getSelection()
    assert.are.equal(selected_r, r)
    assert.are.equal(selected_c, c)

    -- Check working value initially empty (0)
    assert.are.equal(0, board:getWorkingValue(r, c))

    -- Set value to 5
    board:setValue(5)
    assert.are.equal(5, board:getWorkingValue(r, c))

    -- Check we can undo
    assert.True(board:canUndo())
    board:undo()
    assert.are.equal(0, board:getWorkingValue(r, c))

    -- Test notes
    board:setSelection(selected_r, selected_c)
    local ok, err = board:toggleNoteDigit(3)
    assert.True(ok, tostring(err))
    local notes = board:getCellNotes(selected_r, selected_c)
    assert.is_not_nil(notes)
    assert.True(notes[3])

    board:toggleNoteDigit(3)
    notes = board:getCellNotes(selected_r, selected_c)
    assert.is_nil(notes)

    if type(board.clearNotes) == "function" then
      board:clearNotes(selected_r, selected_c)
      notes = board:getCellNotes(selected_r, selected_c)
      assert.is_nil(notes)
    end
  end)

  describe("Serialization and Verification Helpers", function()
    it("should serialize and restore board state", function()
      local class = dofile("plugins/sudoku.koplugin/main.lua")
      local mock_ui = { menu = { registerToMainMenu = function() end } }
      local Sudoku = class:new({ ui = mock_ui })
      local board = Sudoku:getBoard()
      board:generate("medium")

      local serialized = board:serialize()
      assert.is_table(serialized)

      local loaded = board:load(serialized)
      assert.is_true(loaded)
      assert.is_false(board:load(nil))
      assert.is_false(board:load({}))

      board:toggleSolution()
      assert.is_true(board:isShowingSolution())
      board:toggleSolution()

      board:updateWrongMarks()
      assert.is_boolean(board:hasWrongMark(1, 1))
      board:clearWrongMarks()
      assert.is_false(board:hasWrongMark(1, 1))

      local rem = board:getRemainingCells()
      assert.is_number(rem)
    end)
  end)

  describe("SudokuBoardWidget and SudokuScreen UI", function()
    it("should initialize screen, handle inputs, notes mode, and paintTo", function()
      local Blitbuffer = require("ffi/blitbuffer")
      local UIManager = require("ui/uimanager")
      local class = dofile("plugins/sudoku.koplugin/main.lua")
      local mock_ui = { menu = { registerToMainMenu = function() end } }
      local plugin = class:new({ ui = mock_ui })
      plugin:init()

      local menu_items = {}
      plugin:addToMainMenu(menu_items)
      assert.is_table(menu_items.sudoku)

      local orig_show = UIManager.show
      UIManager.show = function(self_uim, widget) end

      plugin:showGame()
      assert.is_table(plugin.screen)
      local screen = plugin.screen

      -- Test input actions
      screen:inputDigit(1)
      screen:toggleNoteMode()
      screen:inputDigit(2)
      screen:toggleNoteMode()
      screen:eraseDigit()
      screen:undoMove()
      screen:checkProgress()
      screen:toggleSolution()
      screen:toggleSolution()
      screen:startNewGame()
      screen:openDifficultyMenu()

      -- Test board widget
      local board_widget = screen.board_widget
      assert.is_table(board_widget)
      if board_widget.paint_rect then
        local r, c = board_widget:getCellFromPoint(board_widget.paint_rect.x + 20, board_widget.paint_rect.y + 20)
        if r and c then
          assert.is_number(r)
          assert.is_number(c)
        end
        board_widget:onTap(nil, { pos = { x = board_widget.paint_rect.x + 20, y = board_widget.paint_rect.y + 20 } })
      end

      -- Paint to real blitbuffer
      local bb = Blitbuffer.new(600, 800)
      screen:paintTo(bb, 0, 0)
      bb:free()

      screen:onClose()
      assert.is_nil(plugin.screen)
      UIManager.show = orig_show
    end)
  end)
end)
