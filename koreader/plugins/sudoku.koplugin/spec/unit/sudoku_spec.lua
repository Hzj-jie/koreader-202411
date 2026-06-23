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
      if selected_r then break end
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
  end)
end)
