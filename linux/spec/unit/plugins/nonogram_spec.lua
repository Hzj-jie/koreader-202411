describe("Nonogram plugin main module", function()
  local Nonogram
  local UIManager, Screen, Blitbuffer

  setup(function()
    require("commonrequire")
    Nonogram = require("plugins/nonogram.koplugin/main")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    Blitbuffer = require("ffi/blitbuffer")
  end)

  local function createMockNonogram()
    local plugin = Nonogram:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/nonogram.koplugin",
    })
    plugin.settings = {
      data = {},
      read = function(self, key)
        return self.data[key]
      end,
      save = function(self, key, val)
        self.data[key] = val
      end,
      flush = function() end,
    }
    return plugin
  end

  it("should initialize Nonogram plugin instance and menu", function()
    local plugin = createMockNonogram()
    assert.is_table(plugin)
    local items = {}
    plugin:addToMainMenu(items)
    assert.is_table(items.nonogram)
    assert.is_function(items.nonogram.callback)
  end)

  it(
    "should generate random puzzle and handle board selections and progress",
    function()
      local plugin = createMockNonogram()
      local board = plugin:getBoard()
      local puzzle = board:generateRandomPuzzle(6, 6, 0.5)
      assert.is_table(puzzle)
      assert.are.equal(6, board:getRowCount())
      assert.are.equal(6, board:getColCount())

      board:setSelection(2, 3)
      local r, c = board:getSelection()
      assert.are.equal(2, r)
      assert.are.equal(3, c)

      -- Clamping
      board:setSelection(100, -5)
      r, c = board:getSelection()
      assert.are.equal(6, r)
      assert.are.equal(1, c)

      -- Row/Col hints
      assert.is_table(board:getRowHints(1))
      assert.is_table(board:getColHints(1))
      assert.is_number(board:getMaxRowHintCount())
      assert.is_number(board:getMaxColHintCount())

      -- Toggle solution
      assert.is_false(board:isShowingSolution())
      board:toggleSolution()
      assert.is_true(board:isShowingSolution())
      board:toggleSolution()
      assert.is_false(board:isShowingSolution())
    end
  )

  it(
    "should apply actions, check satisfaction, and detect conflicts",
    function()
      local plugin = createMockNonogram()
      local board = plugin:getBoard()
      board:generateRandomPuzzle(5, 5, 0.5)
      board:resetProgress()

      board:setSelection(1, 1)
      assert.is_true(board:applyAction("fill"))
      assert.are.equal(1, board:_cellState(1, 1))

      assert.is_true(board:applyAction("mark"))
      assert.are.equal(0, board:_cellState(1, 1))

      assert.is_true(board:applyAction("clear"))
      assert.are.equal(-1, board:_cellState(1, 1))

      assert.is_false(board:applyAction("invalid_action"))

      -- Test row / col satisfaction and solved state
      local rows = board:getRowCount()
      local cols = board:getColCount()
      for row = 1, rows do
        for col = 1, cols do
          board:setSelection(row, col)
          if board.current.solution[row][col] then
            board:applyAction("fill")
          else
            board:applyAction("mark")
          end
        end
      end
      assert.is_true(board:isRowSatisfied(1))
      assert.is_true(board:isColSatisfied(1))
      assert.is_true(board:isSolved())
      assert.is_false(board:hasConflicts())
    end
  )

  it("should serialize and deserialize board state correctly", function()
    local plugin = createMockNonogram()
    local board = plugin:getBoard()
    board:generateRandomPuzzle(5, 5, 0.4)
    board:setSelection(2, 2)
    board:applyAction("fill")

    local state = board:serialize()
    assert.is_table(state)
    assert.is_table(state.puzzle)
    assert.is_table(state.user_grid)

    local plugin2 = createMockNonogram()
    plugin2.settings.data["state"] = state
    local restored_board = plugin2:getBoard()
    assert.are.equal(5, restored_board:getRowCount())
    assert.are.equal(1, restored_board:_cellState(2, 2))
  end)

  it(
    "should manage NonogramScreen interactions, layout, and button callbacks",
    function()
      local plugin = createMockNonogram()
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      local shown_widget
      UIManager.show = function(self, widget)
        shown_widget = widget
      end
      UIManager.close = function() end

      plugin:showGame()
      assert.is_not_nil(plugin.screen)
      assert.are.equal(plugin.screen, shown_widget)

      local screen = plugin.screen
      screen:setActiveAction("fill")
      assert.are.equal("fill", screen.active_action)
      screen:setActiveAction("mark")
      assert.are.equal("mark", screen.active_action)

      screen:onCellActivated(1, 1)
      screen:onAction("clear")
      screen:onHint()
      screen:onCheck()
      screen:toggleSolution()
      screen:toggleSolution()

      -- Test widget touch and painting
      local bb = Blitbuffer.new(Screen:getWidth(), Screen:getHeight())
      screen:paintTo(bb, 0, 0)

      local pt = {
        x = screen.board_widget.paint_rect.x + 5,
        y = screen.board_widget.paint_rect.y + 5,
      }
      screen.board_widget:onTap(nil, pt)

      plugin:onScreenClosed()
      assert.is_nil(plugin.screen)

      UIManager.show = orig_show
      UIManager.close = orig_close
    end
  )

  it(
    "should clear conflict_visible and incorrect_filled when revealHint resolves conflicts [exposes production bug in NonogramBoard:revealHint()]",
    function()
      local plugin = createMockNonogram()
      local board = plugin:getBoard()
      board:generateRandomPuzzle(5, 5, 0.5)
      board:resetProgress()

      -- Find a cell where solution is false
      local wrong_r, wrong_c
      for r = 1, 5 do
        for c = 1, 5 do
          if not board.current.solution[r][c] then
            wrong_r, wrong_c = r, c
            break
          end
        end
        if wrong_r then
          break
        end
      end

      -- Fill the wrong cell to introduce an intentional conflict
      board:setSelection(wrong_r, wrong_c)
      board:applyAction("fill")

      -- Call checkProgress to mark conflicts visible
      local progress = board:checkProgress()
      assert.is_true(progress.conflicts)
      assert.is_true(board:hasConflicts())
      assert.is_true(board:areConflictsVisible())
      assert.is_true(
        board.incorrect_filled[wrong_r]
            and board.incorrect_filled[wrong_r][wrong_c]
          or false
      )

      -- Now reveal hint to fix the incorrect cell
      local ok = board:revealHint()
      assert.is_true(ok)

      -- The conflict has been resolved
      assert.is_false(board:hasConflicts())

      -- revealHint should have cleared conflict_visible and incorrect_filled
      assert.is_false(board:areConflictsVisible())
      assert.is_false(
        board.incorrect_filled[wrong_r]
            and board.incorrect_filled[wrong_r][wrong_c]
          or false
      )
    end
  )
end)
