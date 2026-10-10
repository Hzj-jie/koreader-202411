describe("Solitaire Game plugin", function()
  local Game

  setup(function()
    require("commonrequire")
    Game = require("plugins/solitaire.koplugin/game")
  end)

  it("should initialize default state correctly", function()
    local game = Game:new()
    assert.is_table(game.stock)
    assert.are.equal(0, #game.stock)
    assert.is_table(game.waste)
    assert.are.equal(0, #game.waste)
    assert.are.equal(4, #game.foundations)
    assert.are.equal(7, #game.tableau)
    assert.are.equal(0, game.moves)
    assert.are.equal(0, game.score)
    assert.are.equal(1, game.draw_mode)
    assert.are.equal(0, game.last_draw_count)
    assert.are.equal(100, game.max_history)
    assert.is_false(game.timer_running)
    assert.is_nil(game.start_time)
  end)

  it("should deep copy cards and piles correctly", function()
    local game = Game:new()
    assert.is_nil(game:copyCard(nil))

    local card = { suit = 1, rank = 13, face_up = true }
    local card_copy = game:copyCard(card)
    assert.are.same(card, card_copy)
    card_copy.face_up = false
    assert.is_true(card.face_up)

    local pile = {
      { suit = 1, rank = 1, face_up = false },
      { suit = 2, rank = 2, face_up = true },
    }
    local pile_copy = game:copyPile(pile)
    assert.are.equal(2, #pile_copy)
    assert.are.same(pile, pile_copy)
    pile_copy[1].face_up = true
    assert.is_false(pile[1].face_up)
  end)

  it("should create deck and deal cards to tableau and stock", function()
    local game = Game:new()
    local deck = game:createDeck()
    assert.are.equal(52, #deck)

    game:deal()
    assert.are.equal(0, #game.waste)
    assert.are.equal(24, #game.stock)
    assert.are.equal(0, game.moves)
    assert.are.equal(0, game.score)
    assert.are.equal(0, game.last_draw_count)
    assert.is_true(game.timer_running)
    assert.is_not_nil(game.start_time)

    local tableau_card_count = 0
    for col = 1, 7 do
      assert.are.equal(col, #game.tableau[col])
      tableau_card_count = tableau_card_count + #game.tableau[col]
      for row = 1, col do
        local c = game.tableau[col][row]
        if row == col then
          assert.is_true(c.face_up)
        else
          assert.is_false(c.face_up)
        end
      end
    end
    assert.are.equal(28, tableau_card_count)

    for _, c in ipairs(game.stock) do
      assert.is_false(c.face_up)
    end
  end)

  it("should correctly evaluate card color and display text", function()
    local game = Game:new()
    local c_hearts = { suit = 1, rank = 1, face_up = true }
    local c_diamonds = { suit = 2, rank = 13, face_up = true }
    local c_clubs = { suit = 3, rank = 10, face_up = true }
    local c_spades = { suit = 4, rank = 11, face_up = true }
    local c_hidden = { suit = 1, rank = 1, face_up = false }

    assert.are.equal("red", game:getCardColor(c_hearts))
    assert.are.equal("red", game:getCardColor(c_diamonds))
    assert.are.equal("black", game:getCardColor(c_clubs))
    assert.are.equal("black", game:getCardColor(c_spades))

    assert.are.equal("A♥", game:getCardDisplay(c_hearts))
    assert.are.equal("K♦", game:getCardDisplay(c_diamonds))
    assert.are.equal("10♣", game:getCardDisplay(c_clubs))
    assert.are.equal("J♠", game:getCardDisplay(c_spades))
    assert.are.equal("▒▒▒", game:getCardDisplay(c_hidden))
  end)

  it("should correctly evaluate canPlaceOnTableau rules", function()
    local game = Game:new()
    local empty_pile = {}
    local king = { suit = 1, rank = 13, face_up = true }
    local queen = { suit = 1, rank = 12, face_up = true }

    assert.is_true(game:canPlaceOnTableau(king, empty_pile))
    assert.is_false(game:canPlaceOnTableau(queen, empty_pile))

    local target_red_king = { { suit = 1, rank = 13, face_up = true } }
    local black_queen = { suit = 3, rank = 12, face_up = true }
    local red_queen = { suit = 2, rank = 12, face_up = true }
    local black_jack = { suit = 4, rank = 11, face_up = true }

    assert.is_true(game:canPlaceOnTableau(black_queen, target_red_king))
    assert.is_false(game:canPlaceOnTableau(red_queen, target_red_king))
    assert.is_false(game:canPlaceOnTableau(black_jack, target_red_king))

    local face_down_target = { { suit = 1, rank = 13, face_up = false } }
    assert.is_false(game:canPlaceOnTableau(black_queen, face_down_target))
  end)

  it("should correctly evaluate canPlaceOnFoundation rules", function()
    local game = Game:new()
    local ace_spades = { suit = 4, rank = 1, face_up = true }
    local two_spades = { suit = 4, rank = 2, face_up = true }
    local two_hearts = { suit = 1, rank = 2, face_up = true }
    local three_spades = { suit = 4, rank = 3, face_up = true }

    assert.is_true(game:canPlaceOnFoundation(ace_spades, 1))
    assert.is_false(game:canPlaceOnFoundation(two_spades, 1))

    game.foundations[1] = { ace_spades }
    assert.is_true(game:canPlaceOnFoundation(two_spades, 1))
    assert.is_false(game:canPlaceOnFoundation(two_hearts, 1))
    assert.is_false(game:canPlaceOnFoundation(three_spades, 1))
  end)

  it("should draw cards from stock and recycle waste", function()
    local game = Game:new()
    game.stock = {
      { suit = 1, rank = 1, face_up = false },
      { suit = 1, rank = 2, face_up = false },
      { suit = 1, rank = 3, face_up = false },
    }
    game.waste = {}
    game.draw_mode = 1

    -- Draw 1
    assert.is_true(game:drawFromStock())
    assert.are.equal(1, #game.waste)
    assert.are.equal(2, #game.stock)
    assert.are.equal(3, game.waste[1].rank)
    assert.is_true(game.waste[1].face_up)
    assert.are.equal(1, game.last_draw_count)

    -- Draw 3 mode
    game:setDrawMode(3)
    assert.are.equal(3, game.draw_mode)
    assert.is_true(game:drawFromStock())
    assert.are.equal(3, #game.waste)
    assert.are.equal(0, #game.stock)
    assert.are.equal(2, game.last_draw_count)

    -- Recycle waste back to stock
    game.score = 50
    assert.is_true(game:drawFromStock())
    assert.are.equal(0, #game.waste)
    assert.are.equal(3, #game.stock)
    assert.are.equal(0, game.last_draw_count)
    assert.are.equal(30, game.score)

    -- Empty stock and empty waste
    game.stock = {}
    game.waste = {}
    assert.is_false(game:drawFromStock())
  end)

  it("should manage timer methods and formatting", function()
    local game = Game:new()
    assert.are.equal("0:00", game:formatTime(0))
    assert.are.equal("1:05", game:formatTime(65))
    assert.are.equal("12:34", game:formatTime(754))

    game:startTimer()
    assert.is_true(game.timer_running)
    assert.is_number(game:getElapsedTime())

    game:stopTimer()
    assert.is_false(game.timer_running)
    local elapsed = game:getElapsedTime()
    assert.is_number(elapsed)
  end)

  it("should move cards to foundation from waste and tableau", function()
    local game = Game:new()
    local five = { suit = 1, rank = 5, face_up = true }
    game.waste = { five }
    assert.is_false(game:moveToFoundation("waste", nil, 1))

    local ace = { suit = 1, rank = 1, face_up = true }
    game.waste = { ace }
    assert.is_true(game:moveToFoundation("waste", nil, 1))
    assert.are.equal(0, #game.waste)
    assert.are.equal(1, #game.foundations[1])
    assert.are.equal(10, game.score)
    assert.are.equal(1, game.moves)

    local two = { suit = 1, rank = 2, face_up = true }
    local hidden = { suit = 2, rank = 5, face_up = false }
    game.tableau[1] = { hidden, two }

    assert.is_true(game:moveToFoundation("tableau", 1, 1))
    assert.are.equal(1, #game.tableau[1])
    assert.is_true(game.tableau[1][1].face_up)
    assert.are.equal(25, game.score)
    assert.are.equal(2, game.moves)

    assert.is_false(game:moveToFoundation("unknown", 1, 1))
  end)

  it("should move cards between tableau columns and from foundation", function()
    local game = Game:new()
    local king = { suit = 1, rank = 13, face_up = true }
    local queen = { suit = 4, rank = 12, face_up = true }
    local hidden = { suit = 3, rank = 8, face_up = false }
    game.tableau[1] = { hidden, king, queen }
    game.tableau[2] = {}

    -- Move king and queen to empty tableau 2
    assert.is_true(game:moveToTableau("tableau", 1, 2, 2))
    assert.are.equal(1, #game.tableau[1])
    assert.is_true(game.tableau[1][1].face_up)
    assert.are.equal(2, #game.tableau[2])
    assert.are.equal(10, game.score)
    assert.are.equal(1, game.moves)

    -- Move from waste to tableau
    local jack = { suit = 2, rank = 11, face_up = true }
    game.waste = { jack }
    assert.is_true(game:moveToTableau("waste", nil, 1, 2))
    assert.are.equal(0, #game.waste)
    assert.are.equal(3, #game.tableau[2])
    assert.are.equal(15, game.score)

    -- Move from foundation to tableau
    local ten = { suit = 3, rank = 10, face_up = true }
    game.foundations[3] = { ten }
    assert.is_true(game:moveToTableau("foundation", 3, 1, 2))
    assert.are.equal(0, #game.foundations[3])
    assert.are.equal(4, #game.tableau[2])
    assert.are.equal(0, game.score)

    assert.is_false(game:moveToTableau("invalid", 1, 1, 2))
  end)

  it("should support autoMoveToFoundation and checkWin", function()
    local game = Game:new()
    local ace_hearts = { suit = 1, rank = 1, face_up = true }
    game.waste = { ace_hearts }

    assert.is_true(game:autoMoveToFoundation())
    assert.are.equal(1, #game.foundations[1])
    assert.is_false(game:checkWin())

    local ace_diamonds = { suit = 2, rank = 1, face_up = true }
    game.tableau[3] = { ace_diamonds }
    assert.is_true(game:autoMoveToFoundation())
    assert.are.equal(1, #game.foundations[2])

    for f = 1, 4 do
      game.foundations[f] = {}
      for r = 1, 13 do
        table.insert(
          game.foundations[f],
          { suit = f, rank = r, face_up = true }
        )
      end
    end
    assert.is_true(game:checkWin())
  end)

  it("should provide hints for moves and drawing", function()
    local game = Game:new()
    local ace = { suit = 1, rank = 1, face_up = true }
    game.waste = { ace }
    local hint1 = game:getHint()
    assert.is_table(hint1)
    assert.are.equal("waste_to_foundation", hint1.type)
    assert.are.equal(1, hint1.foundation)

    game.waste = {}
    game.tableau[2] = { ace }
    local hint2 = game:getHint()
    assert.is_table(hint2)
    assert.are.equal("tableau_to_foundation", hint2.type)

    local red_king = { suit = 1, rank = 13, face_up = true }
    local black_queen = { suit = 3, rank = 12, face_up = true }
    game.tableau[2] = { red_king }
    game.waste = { black_queen }
    local hint3 = game:getHint()
    assert.is_table(hint3)
    assert.are.equal("waste_to_tableau", hint3.type)

    game.waste = {}
    game.tableau[4] = { black_queen }
    local hint4 = game:getHint()
    assert.is_table(hint4)
    assert.are.equal("tableau_to_tableau", hint4.type)

    game.tableau = { {}, {}, {}, {}, {}, {}, {} }
    game.stock = { { suit = 1, rank = 5, face_up = false } }
    local hint5 = game:getHint()
    assert.is_table(hint5)
    assert.are.equal("draw", hint5.type)

    game.stock = {}
    assert.is_nil(game:getHint())
  end)

  it("should serialize and deserialize save data correctly", function()
    local game = Game:new()
    game:deal()
    game.score = 42
    game.moves = 7
    game.draw_mode = 3
    game.last_draw_count = 2

    local data = game:toSaveData()
    assert.is_table(data)
    assert.are.equal(42, data.score)
    assert.are.equal(7, data.moves)
    assert.are.equal(3, data.draw_mode)
    assert.are.equal(2, data.last_draw_count)

    local restored_game = Game:new()
    assert.is_false(restored_game:fromSaveData(nil))
    assert.is_true(restored_game:fromSaveData(data))
    assert.are.equal(42, restored_game.score)
    assert.are.equal(7, restored_game.moves)
    assert.are.equal(3, restored_game.draw_mode)
    assert.are.equal(2, restored_game.last_draw_count)
    assert.are.equal(#game.stock, #restored_game.stock)
  end)

  it(
    "should manage history, undo, and cap history size at max_history",
    function()
      local game = Game:new()
      assert.is_false(game:canUndo())
      assert.is_false(game:undo())

      game.max_history = 3
      game.score = 10
      game:saveState()
      game.score = 20
      game:saveState()
      game.score = 30
      game:saveState()
      game.score = 40

      assert.are.equal(3, #game.history)
      assert.is_true(game:canUndo())
      assert.is_true(game:undo())
      assert.are.equal(30, game.score)

      game:clearHistory()
      assert.are.equal(0, #game.history)
      assert.is_false(game:canUndo())
    end
  )

  it(
    "should restore last_draw_count on undo [exposes production bug in Game:saveState()]",
    function()
      local game = Game:new()
      game:setDrawMode(3)
      game.stock = {
        { suit = 1, rank = 1, face_up = false },
        { suit = 1, rank = 2, face_up = false },
        { suit = 1, rank = 3, face_up = false },
      }
      game.waste = {}

      -- Drawing 3 cards sets last_draw_count to 3
      game:drawFromStock()
      assert.are.equal(3, game.last_draw_count)
      assert.are.equal(3, #game.waste)
      assert.are.equal(0, #game.stock)

      -- Next draw from stock recycles waste, resetting last_draw_count to 0
      game:drawFromStock()
      assert.are.equal(0, game.last_draw_count)

      -- Calling undo should restore the previous state including last_draw_count = 3
      assert.is_true(game:undo())
      assert.are.equal(3, game.last_draw_count)
    end
  )
end)
