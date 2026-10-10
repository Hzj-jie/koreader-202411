describe("Checkers AI module", function()
  local AI, Game

  setup(function()
    require("commonrequire")
    AI = require("plugins/checkers.koplugin/ai")
    Game = require("plugins/checkers.koplugin/game")
  end)

  describe("best_move edge cases", function()
    it("should return nil when there are no legal moves available", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        if piece.player == 1 then
          piece.captured = true
          piece.position = nil
        end
      end
      game.board.player_turn = 1
      game.board.searcher:build(game.board)

      assert.is_nil(AI.best_move(game, 1))
    end)

    it("should return immediately when only one legal move is available", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end

      -- Single piece at pos 5 (odd row edge) with single diagonal move to pos 9
      local p1 = game.board.pieces[1]
      p1.captured = false
      p1.player = 1
      p1.position = 5

      game.board.searcher:build(game.board)

      local moves = game:get_possible_moves()
      assert.are.equal(1, #moves)

      local best = AI.best_move(game, 1)
      assert.is_table(best)
      assert.are.same(moves[1], best)
    end)
  end)

  describe("best_move evaluation and non-mutation", function()
    it("should select capturing move and avoid mutating caller game state at depth 1", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end

      -- P1 at pos 10, enemy P2 at pos 14 (destination pos 17 open).
      -- P1 also at pos 12 (can make positional move to pos 15).
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

      local turn_before = game:whose_turn()
      local moves_since_before = game.moves_since_last_capture
      local pos10_before = game:get_piece_at(10)

      local best = AI.best_move(game, 1)
      assert.is_table(best)
      -- Forced capture of enemy at pos 14
      assert.are.equal(10, best[1])
      assert.are.equal(17, best[2])

      -- Verify game was NOT mutated
      assert.are.equal(turn_before, game:whose_turn())
      assert.are.equal(moves_since_before, game.moves_since_last_capture)
      assert.are.same(pos10_before, game:get_piece_at(10))
      assert.is_not_nil(game:get_piece_at(14))
    end)

    it("should search depth 2 and handle mid-jump continuation", function()
      local game = Game.new()
      for _, piece in ipairs(game.board.pieces) do
        piece.captured = true
        piece.position = nil
      end

      -- P1 piece at pos 10, enemies at pos 14 and pos 22.
      -- First jump 10 -> 17 puts game in mid-jump continuation.
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

      local best = AI.best_move(game, 2)
      assert.is_table(best)
      assert.are.equal(10, best[1])
      assert.are.equal(17, best[2])

      -- Advance game to mid-jump state and query AI
      game:move(best[1], best[2])
      assert.is_true(game:is_mid_jump())

      local continuation = AI.best_move(game, 2)
      assert.is_table(continuation)
      assert.are.equal(17, continuation[1])
      assert.are.equal(26, continuation[2])
    end)
  end)
end)
