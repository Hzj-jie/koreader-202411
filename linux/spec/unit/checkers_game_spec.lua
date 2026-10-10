describe("Checkers plugin Game logic module", function()
  local Game

  setup(function()
    require("commonrequire")
    Game = require("plugins/checkers.koplugin/game")
  end)

  describe("Initialization & basic queries", function()
    it("should initialize Checkers Game instance with correct initial state", function()
      local game = Game.new()
      assert.is_table(game)
      assert.are.equal(1, game:whose_turn())
      assert.are.equal(0, game.moves_since_last_capture)
      assert.is_false(game:can_undo())
      assert.is_false(game:is_mid_jump())
      assert.is_nil(game:get_mid_jump_piece_pos())
      assert.is_false(game:is_over())
      assert.is_nil(game:get_winner())

      -- Initial pieces layout (1-12: player 1, 13-20: empty, 21-32: player 2)
      for pos = 1, 12 do
        local p = game:get_piece_at(pos)
        assert.is_table(p)
        assert.are.equal(1, p.player)
        assert.is_false(p.king)
      end
      for pos = 13, 20 do
        assert.is_nil(game:get_piece_at(pos))
      end
      for pos = 21, 32 do
        local p = game:get_piece_at(pos)
        assert.is_table(p)
        assert.are.equal(2, p.player)
        assert.is_false(p.king)
      end
    end)

    it("should generate legal opening moves for player 1", function()
      local game = Game.new()
      local all_moves = game:get_possible_moves()
      assert.is_table(all_moves)
      assert.is_true(#all_moves > 0)

      -- Only front-row pieces (positions 9-12) can move forward initially
      local p9_moves = game:get_moves_for_piece(9)
      assert.is_table(p9_moves)
      assert.is_true(#p9_moves > 0)

      local p1_moves = game:get_moves_for_piece(1)
      assert.is_table(p1_moves)
      assert.are.equal(0, #p1_moves)
    end)
  end)

  describe("Movement, turns, and capture rules", function()
    it("should reject invalid moves and apply valid positional moves", function()
      local game = Game.new()
      -- Moving non-existent or blocked piece
      assert.is_false(game:move(1, 5))
      assert.is_false(game:move(9, 20))

      -- Apply valid move from pos 9
      local moves = game:get_moves_for_piece(9)
      local dest = moves[1][2]
      assert.is_true(game:move(9, dest))

      assert.is_nil(game:get_piece_at(9))
      local p = game:get_piece_at(dest)
      assert.is_not_nil(p)
      assert.are.equal(1, p.player)

      assert.are.equal(1, game.moves_since_last_capture)
      assert.are.equal(2, game:whose_turn())
    end)

    it("should enforce mandatory capture rule and execute single capture", function()
      local game = Game.new()
      -- Clear all pieces and place a specific scenario:
      -- Player 1 piece at 10, Player 2 piece at 14, destination 17 is empty
      -- Player 1 also has a piece at 9 that could make a positional move to 13
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end
      local p1 = game.board.pieces[1]
      p1.captured = false
      p1.player = 1
      p1.position = 10

      local p2 = game.board.pieces[2]
      p2.captured = false
      p2.player = 1
      p2.position = 12

      local enemy = game.board.pieces[13]
      enemy.captured = false
      enemy.player = 2
      enemy.position = 14

      game.board.searcher:build(game.board)

      -- Mandatory capture: possible_moves must only contain capture moves from 10 to 17
      local possible = game:get_possible_moves()
      assert.are.equal(1, #possible)
      assert.are.equal(10, possible[1][1])
      assert.are.equal(17, possible[1][2])

      -- Non-capture move from 12 should be rejected
      assert.is_false(game:move(12, 15))

      -- Capture move succeeds
      game.moves_since_last_capture = 5
      assert.is_true(game:move(10, 17))
      assert.are.equal(0, game.moves_since_last_capture)
      assert.is_nil(game:get_piece_at(10))
      assert.is_nil(game:get_piece_at(14)) -- captured enemy removed
      assert.is_not_nil(game:get_piece_at(17))
      assert.are.equal(2, game:whose_turn())
      assert.is_false(game:is_mid_jump())
    end)

    it("should handle multi-jump continuation and restrict possible moves", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end

      -- P1 at pos 10, enemies at pos 14 and pos 22.
      -- Row 2 (pos 10) jumps over row 3 (pos 14) to row 4 (pos 17).
      -- From row 4 (pos 17), jumps over row 5 (pos 22) to row 6 (pos 26).
      local p1 = game.board.pieces[1]
      p1.captured = false
      p1.player = 1
      p1.position = 10

      local e1 = game.board.pieces[13]
      e1.captured = false
      e1.player = 2
      e1.position = 14

      local e2 = game.board.pieces[14]
      e2.captured = false
      e2.player = 2
      e2.position = 22

      game.board.searcher:build(game.board)

      assert.is_true(game:move(10, 17))
      -- Mid-jump continuation
      assert.is_true(game:is_mid_jump())
      assert.are.equal(17, game:get_mid_jump_piece_pos())
      assert.are.equal(1, game:whose_turn()) -- turn retained during multi-jump

      local further = game:get_possible_moves()
      assert.are.equal(1, #further)
      assert.are.equal(17, further[1][1])
      assert.are.equal(26, further[1][2])

      -- Cannot undo mid-jump
      assert.is_false(game:can_undo())
      assert.is_false(game:undo())

      -- Complete second jump
      assert.is_true(game:move(17, 26))
      assert.is_false(game:is_mid_jump())
      assert.are.equal(2, game:whose_turn())
      assert.is_not_nil(game:get_piece_at(26))
      assert.is_nil(game:get_piece_at(22))
    end)

    it("should promote piece to king upon reaching enemy back rank and end turn", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end

      -- Player 1 at pos 22 (row 5), enemy at pos 26 (row 6), destination pos 31 (row 7 = back rank)
      local p1 = game.board.pieces[1]
      p1.captured = false
      p1.player = 1
      p1.position = 22

      local enemy = game.board.pieces[13]
      enemy.captured = false
      enemy.player = 2
      enemy.position = 26

      -- Another enemy at pos 27 to test that king promotion does not continue jumps
      local enemy2 = game.board.pieces[14]
      enemy2.captured = false
      enemy2.player = 2
      enemy2.position = 27

      game.board.searcher:build(game.board)

      assert.is_true(game:move(22, 31))
      local crowned = game:get_piece_at(31)
      assert.is_not_nil(crowned)
      assert.is_true(crowned.king)
      -- Turn ends immediately on king promotion
      assert.is_false(game:is_mid_jump())
      assert.are.equal(2, game:whose_turn())

      -- Test king movement: crowned king can move backwards
      -- Switch back to player 1
      game.board.player_turn = 1
      game.board.searcher:build(game.board)
      local king_moves = game:get_moves_for_piece(31)
      assert.is_true(#king_moves > 0)
    end)
  end)

  describe("Undo, game over, winner, and clone", function()
    it("should undo single and multi-jump moves properly", function()
      local game = Game.new()
      -- Single positional move
      local initial_turn = game:whose_turn()
      assert.is_true(game:move(9, 13))
      assert.is_true(game:can_undo())
      assert.is_true(game:undo())
      assert.are.equal(initial_turn, game:whose_turn())
      assert.is_not_nil(game:get_piece_at(9))
      assert.is_nil(game:get_piece_at(13))
      assert.are.equal(0, game.moves_since_last_capture)

      -- Multi-jump undo
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end
      local p1 = game.board.pieces[1]
      p1.captured = false
      p1.player = 1
      p1.position = 10

      local e1 = game.board.pieces[13]
      e1.captured = false
      e1.player = 2
      e1.position = 14

      local e2 = game.board.pieces[14]
      e2.captured = false
      e2.player = 2
      e2.position = 22

      game.board.searcher:build(game.board)
      game:move(10, 17)
      game:move(17, 26)
      assert.are.equal(2, game:whose_turn())

      -- Undoing should collapse entire multi-jump turn back to position 10
      assert.is_true(game:undo())
      assert.are.equal(1, game:whose_turn())
      assert.is_not_nil(game:get_piece_at(10))
      assert.is_not_nil(game:get_piece_at(14))
      assert.is_not_nil(game:get_piece_at(22))
      assert.is_nil(game:get_piece_at(26))
      assert.is_false(game:is_mid_jump())
    end)

    it("should detect game over on non-capture limit and no legal moves", function()
      local game = Game.new()
      assert.is_false(game:is_over())

      -- Non-capture move limit reached (40 moves)
      game.moves_since_last_capture = 40
      assert.is_true(game:is_over())
      -- 40-move draw has no winner
      assert.is_nil(game:get_winner())

      -- No legal moves for active player -> opponent wins
      game.moves_since_last_capture = 0
      for _, piece in ipairs(game.board.pieces) do
        if piece.player == 1 then
          piece.captured = true
          piece.position = nil
        end
      end
      game.board.player_turn = 1
      game.board.searcher:build(game.board)

      assert.is_true(game:is_over())
      assert.are.equal(2, game:get_winner())
    end)

    it("should clone game state into an independent copy", function()
      local game = Game.new()
      game:move(9, 13)
      local clone = game:clone()

      assert.is_table(clone)
      assert.are.equal(game:whose_turn(), clone:whose_turn())
      assert.are.equal(game.moves_since_last_capture, clone.moves_since_last_capture)
      assert.are.same(game:get_piece_at(13), clone:get_piece_at(13))

      -- Mutating clone must not affect original
      clone:move(22, 18)
      assert.is_nil(game:get_piece_at(18))
      assert.is_not_nil(clone:get_piece_at(18))
    end)
  end)
end)
