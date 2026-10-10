describe("SlidePuzzleGame module", function()
  local Game

  setup(function()
    require("commonrequire")
    Game = require("plugins/slidepuzzle.koplugin/slidepuzzle_game")
  end)

  describe("Initialization, bounds, and resetToSolved", function()
    it("should clamp grid sizes to [MIN_SIZE, MAX_SIZE] and initialize solved state", function()
      assert.are.equal(3, Game.getMinSize())
      assert.are.equal(7, Game.getMaxSize())

      local g_under = Game:new(1)
      assert.are.equal(3, g_under:getSize())

      local g_over = Game:new(10)
      assert.are.equal(7, g_over:getSize())

      local g_nil = Game:new(nil)
      assert.are.equal(3, g_nil:getSize())

      local g3 = Game:new(3)
      assert.are.equal(3, g3:getSize())
      assert.is_true(g3:isWon())
      assert.is_false(g3:hasStarted())
      assert.are.equal(0, g3:getMoves())
      assert.are.equal(0, g3:getElapsed())

      local er, ec = g3:getEmpty()
      assert.are.equal(3, er)
      assert.are.equal(3, ec)

      local grid = g3:getGrid()
      assert.are.equal(1, grid[1][1])
      assert.are.equal(2, grid[1][2])
      assert.are.equal(3, grid[1][3])
      assert.are.equal(4, grid[2][1])
      assert.are.equal(8, grid[3][2])
      assert.are.equal(0, grid[3][3])
    end)

    it("should reset modified board back to solved state", function()
      local g = Game:new(3)
      g.grid[3][3] = 8
      g.grid[3][2] = 0
      g.empty_r, g.empty_c = 3, 2
      g.moves = 10
      g.elapsed = 50
      g.started = true
      g.won = false

      g:resetToSolved()
      assert.is_true(g:isWon())
      assert.is_false(g:hasStarted())
      assert.are.equal(0, g:getMoves())
      assert.are.equal(0, g:getElapsed())
      assert.are.equal(0, g.grid[3][3])
      assert.are.equal(8, g.grid[3][2])
    end)
  end)

  describe("Shuffling", function()
    it("should produce a valid unsolved permutation with zero moves and reset status", function()
      local g = Game:new(3)
      g:shuffle()

      assert.is_false(g:isWon())
      assert.is_false(g:hasStarted())
      assert.are.equal(0, g:getMoves())
      assert.are.equal(0, g:getElapsed())

      -- Verify permutation contains all tiles 0..8 exactly once
      local counts = {}
      for r = 1, 3 do
        for c = 1, 3 do
          local val = g.grid[r][c]
          counts[val] = (counts[val] or 0) + 1
        end
      end

      for i = 0, 8 do
        assert.are.equal(1, counts[i])
      end
    end)
  end)

  describe("moveTileAt and winning conditions", function()
    it("should reject moves when game is already won, out of bounds, or not adjacent", function()
      local g = Game:new(3)
      -- Already won
      assert.is_false(g:moveTileAt(3, 2))

      -- Mark game as not won for boundary testing
      g.won = false
      -- Out of bounds
      assert.is_false(g:moveTileAt(0, 1))
      assert.is_false(g:moveTileAt(4, 3))
      assert.is_false(g:moveTileAt(3, 0))
      assert.is_false(g:moveTileAt(3, 4))

      -- Clicking the empty cell itself
      assert.is_false(g:moveTileAt(3, 3))

      -- Diagonal or distant cell
      assert.is_false(g:moveTileAt(1, 1))
      assert.is_false(g:moveTileAt(2, 2))
    end)

    it("should swap adjacent tile with empty slot, increment moves, and detect win", function()
      local g = Game:new(3)
      -- Setup one move away from solved: swap (3, 2) and (3, 3)
      g.grid[3][2], g.grid[3][3] = 0, 8
      g.empty_r, g.empty_c = 3, 2
      g.won = false

      -- Move tile at (3, 3) into empty slot at (3, 2)
      local ok, prev_er, prev_ec = g:moveTileAt(3, 3)
      assert.is_true(ok)
      assert.are.equal(3, prev_er)
      assert.are.equal(2, prev_ec)
      assert.are.equal(1, g:getMoves())
      assert.is_true(g:hasStarted())
      assert.are.equal(8, g.grid[3][2])
      assert.are.equal(0, g.grid[3][3])
      assert.are.equal(3, g.empty_r)
      assert.are.equal(3, g.empty_c)

      -- Solved state reached
      assert.is_true(g:isWon())

      -- Further moves should be rejected once won
      assert.is_false(g:moveTileAt(3, 2))
    end)
  end)

  describe("slide and addElapsed", function()
    it("should slide tiles via directional swipes", function()
      local g = Game:new(3)
      -- Empty slot at (2, 2) with won = false
      g.grid[3][3] = g.grid[2][2]
      g.grid[2][2] = 0
      g.empty_r, g.empty_c = 2, 2
      g.won = false

      -- Invalid swipe direction
      assert.is_false(g:slide("diagonal"))
      assert.is_false(g:slide(nil))

      -- Swipe "left": tile to the right (2, 3) slides left into (2, 2)
      local tile_r2c3 = g.grid[2][3]
      assert.is_true(g:slide("left"))
      assert.are.equal(tile_r2c3, g.grid[2][2])
      assert.are.equal(0, g.grid[2][3])
      assert.are.equal(2, g.empty_r)
      assert.are.equal(3, g.empty_c)

      -- Swipe "right": tile to the left (2, 2) slides right into (2, 3)
      assert.is_true(g:slide("right"))
      assert.are.equal(0, g.grid[2][2])
      assert.are.equal(tile_r2c3, g.grid[2][3])

      -- Swipe "up": tile below (3, 2) slides up into (2, 2)
      local tile_r3c2 = g.grid[3][2]
      assert.is_true(g:slide("up"))
      assert.are.equal(tile_r3c2, g.grid[2][2])
      assert.are.equal(0, g.grid[3][2])

      -- Swipe "down": tile above (2, 2) slides down into (3, 2)
      assert.is_true(g:slide("down"))
      assert.are.equal(0, g.grid[2][2])
      assert.are.equal(tile_r3c2, g.grid[3][2])
    end)

    it("should accumulate elapsed time only for positive numbers", function()
      local g = Game:new(3)
      assert.are.equal(0, g:getElapsed())

      g:addElapsed(15)
      assert.are.equal(15, g:getElapsed())

      g:addElapsed(10.5)
      assert.are.equal(25.5, g:getElapsed())

      -- Non-positive or invalid deltas ignored
      g:addElapsed(0)
      assert.are.equal(25.5, g:getElapsed())

      g:addElapsed(-5)
      assert.are.equal(25.5, g:getElapsed())

      g:addElapsed("10")
      assert.are.equal(25.5, g:getElapsed())

      g:addElapsed(nil)
      assert.are.equal(25.5, g:getElapsed())
    end)
  end)

  describe("Serialization and Deserialization", function()
    it("should serialize and deserialize game state accurately", function()
      local g = Game:new(3)
      g:shuffle()
      g.moves = 14
      g.elapsed = 120
      g.started = true

      local data = g:serialize()
      assert.is_table(data)
      assert.are.equal(3, data.size)
      assert.are.equal(14, data.moves)
      assert.are.equal(120, data.elapsed)
      assert.is_true(data.started)
      assert.is_false(data.won)

      local restored = Game.deserialize(data, 3)
      assert.is_table(restored)
      assert.are.equal(3, restored:getSize())
      assert.are.equal(14, restored:getMoves())
      assert.are.equal(120, restored:getElapsed())
      assert.is_true(restored:hasStarted())
      assert.is_false(restored:isWon())

      for r = 1, 3 do
        for c = 1, 3 do
          assert.are.equal(g.grid[r][c], restored.grid[r][c])
        end
      end
    end)

    it("should fall back to a freshly shuffled board on corrupt data", function()
      -- Non-table data
      local g1 = Game.deserialize(nil, 3)
      assert.is_table(g1)
      assert.is_false(g1:isWon())

      -- Non-table grid
      local g2 = Game.deserialize({ size = 3, grid = "corrupted" }, 3)
      assert.is_table(g2)
      assert.is_false(g2:isWon())

      -- Row not a table
      local g3 = Game.deserialize({ size = 3, grid = { { 1, 2, 3 }, "bad_row", { 7, 8, 0 } } }, 3)
      assert.is_table(g3)
      assert.is_false(g3:isWon())

      -- Duplicate tile
      local g4 = Game.deserialize({
        size = 3,
        grid = {
          { 1, 2, 3 },
          { 4, 5, 5 }, -- duplicate 5
          { 7, 8, 0 },
        },
      }, 3)
      assert.is_table(g4)
      assert.is_false(g4:isWon())

      -- Out of range tile
      local g5 = Game.deserialize({
        size = 3,
        grid = {
          { 1, 2, 3 },
          { 4, 5, 99 }, -- out of range
          { 7, 8, 0 },
        },
      }, 3)
      assert.is_table(g5)
      assert.is_false(g5:isWon())

      -- Missing 0
      local g6 = Game.deserialize({
        size = 3,
        grid = {
          { 1, 2, 3 },
          { 4, 5, 6 },
          { 7, 8, 9 }, -- no 0
        },
      }, 3)
      assert.is_table(g6)
      assert.is_false(g6:isWon())
    end)
  end)
end)
