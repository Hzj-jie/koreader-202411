describe("Checkers main plugin module", function()
  local Checkers, AI, Game, UIManager, Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Checkers = require("plugins/checkers.koplugin/main")
    AI = require("plugins/checkers.koplugin/ai")
    Game = require("plugins/checkers.koplugin/game")
    UIManager = require("ui/uimanager")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  it("should expose Checkers main plugin class and handle settings", function()
    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    instance:init()

    instance.human[1] = true
    instance.human[2] = true
    instance.ai_depth = 3
    instance:saveSettings()
    instance:loadSettings()
    assert.is_true(instance.human[1])
    assert.is_true(instance.human[2])
    assert.are.equal(3, instance.ai_depth)

    local menu_items = {}
    instance:addToMainMenu(menu_items)
    assert.is_table(menu_items.checkers)
  end)

  it("should format _mode_label and _turn_text for all game states", function()
    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    instance:init()
    instance.game = Game.new()

    -- Mode labels
    instance.human[1] = true
    instance.human[2] = true
    assert.are.equal("HvH", instance:_mode_label())
    instance.human[2] = false
    assert.are.equal("HvC", instance:_mode_label())
    instance.human[1] = false
    assert.are.equal("CvC", instance:_mode_label())
    instance.human[2] = true
    assert.are.equal("CvH", instance:_mode_label())

    -- Turn text - Black human turn
    instance.human[1] = true
    assert.are.equal("Black's turn", instance:_turn_text())

    -- Turn text - Black AI thinking
    instance.human[1] = false
    assert.are.equal("AI thinking…", instance:_turn_text())

    -- Mock game over states
    local old_is_over = instance.game.is_over
    local old_get_winner = instance.game.get_winner
    instance.game.is_over = function()
      return true
    end

    instance.game.get_winner = function()
      return 1
    end
    assert.are.equal("Black wins!", instance:_turn_text())

    instance.game.get_winner = function()
      return 2
    end
    assert.are.equal("White wins!", instance:_turn_text())

    instance.game.get_winner = function()
      return 0
    end
    assert.are.equal("Draw!", instance:_turn_text())

    instance.game.is_over = old_is_over
    instance.game.get_winner = old_get_winner
  end)

  it(
    "should manage game lifecycle, layout, moves, AI, undo, and dialogs",
    function()
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      local orig_schedule = UIManager.scheduleIn
      UIManager.show = function() end
      UIManager.close = function() end
      UIManager.scheduleIn = function(self_uim, delay, fn)
        fn()
      end

      local instance = Checkers:new({
        ui = {
          menu = { registerToMainMenu = function() end },
        },
      })
      instance:init()

      -- Start Game
      instance:startGame()
      assert.is_table(instance.game)
      assert.is_table(instance.board)
      assert.is_table(instance.status_bar)

      -- Status updates
      instance:updateStatus()

      -- Moves and AI
      local moves = instance.game:get_possible_moves()
      if #moves > 0 then
        instance.game:move(moves[1][1], moves[1][2])
        instance:onMoveExecuted(moves[1][1], moves[1][2])
      end
      instance:doAIMove()

      -- Undo
      instance:doUndo()

      -- Ask new game and reset
      instance:askNewGame()
      instance:resetGame()

      -- Game over
      instance:showGameOver()

      -- Settings dialog
      instance:openSettings()

      -- Paint to Blitbuffer
      local bb =
        Blitbuffer.new(instance.full_width or 600, instance.full_height or 800)
      instance:paintTo(bb, 0, 0)
      bb:free()

      -- Handle events
      assert.is_true(instance:onCheckersStart())
      assert.is_true(instance:handleEvent({ handler = "onCheckersStart" }))

      UIManager.show = orig_show
      UIManager.close = orig_close
      UIManager.scheduleIn = orig_schedule
    end
  )

  it("should find best move using AI.best_move at normal depth", function()
    local game = Game.new()
    local best = AI.best_move(game, 2)
    assert.is_table(best)
    assert.are.equal(2, #best)
    assert.is_number(best[1])
    assert.is_number(best[2])
  end)

  it(
    "should schedule AI move after doUndo() leaves game on AI turn [exposes production bug in Checkers:doUndo()]",
    function()
      local scheduled = false
      local old_schedule = UIManager.scheduleIn
      UIManager.scheduleIn = function(self_uim, delay, fn)
        scheduled = true
      end

      local instance = Checkers:new({
        ui = {
          menu = { registerToMainMenu = function() end },
        },
      })
      instance:init()
      -- Black (1) is AI, White (2) is Human
      instance.human[1] = false
      instance.human[2] = true

      instance.game = Game.new()
      instance.board = {
        game = instance.game,
        _clear_selection = function() end,
        updateBoard = function() end,
      }
      instance.status_bar = {
        setTitle = function() end,
        setSubTitle = function() end,
      }

      -- Black (AI) makes opening move
      local m1 = instance.game:get_possible_moves()[1]
      instance.game:move(m1[1], m1[2])
      assert.are.equal(2, instance.game:whose_turn())

      -- White (Human) makes move 2
      local m2 = instance.game:get_possible_moves()[1]
      instance.game:move(m2[1], m2[2])
      assert.are.equal(1, instance.game:whose_turn())

      -- First undo: undid White's move, turn is White (Human)
      instance:doUndo()
      assert.are.equal(2, instance.game:whose_turn())
      assert.is_false(scheduled)

      -- Second undo: undid Black's opening move, turn is now Black (AI)
      scheduled = false
      instance:doUndo()
      assert.are.equal(1, instance.game:whose_turn())
      assert.is_false(instance.human[1])

      -- Production bug: doUndo() leaves game on AI's turn without calling scheduleAIMove()
      assert.is_true(scheduled)

      UIManager.scheduleIn = old_schedule
    end
  )

  it(
    "should evaluate AI.best_move at depth 0 without infinite recursion [exposes production bug in AI.alpha_beta()]",
    function()
      local game = Game.new()
      -- Production bug: ai.lua line 75 checks `depth == 0` instead of `depth <= 0`.
      -- With depth = 0, `next_depth = depth - 1` becomes -1, causing infinite recursion
      -- down the game tree. We install a call-counter hook to bound runaway recursion.
      local call_count = 0
      debug.sethook(function()
        call_count = call_count + 1
        if call_count > 50 then
          debug.sethook()
          error("infinite recursion in alpha_beta: depth <= 0 not handled")
        end
      end, "c")

      local ok, best = pcall(function()
        return AI.best_move(game, 0)
      end)
      debug.sethook()

      assert.is_true(ok)
      assert.is_not_nil(best)
    end
  )
end)
