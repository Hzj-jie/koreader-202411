describe("SokobanGame module", function()
  local SokobanGame

  setup(function()
    require("commonrequire")
    SokobanGame = require("plugins/sokoban.koplugin/sokoban_game")
  end)

  describe("XSB parsing and initialization", function()
    it("should parse XSB levels, strip comments and blank lines, and map characters", function()
      local xsb = [[
; Level title comment
; Author: Test

######
#@ $ .#
#+ * -#
######

; Trailing comment
]]
      local game = SokobanGame.from_xsb(xsb)
      assert.is_table(game)
      assert.are.equal(4, game.rows)
      assert.are.equal(7, game.cols)

      -- Row 1: "######" (plus trailing space for max_cols 7)
      assert.are.equal(SokobanGame.WALL, game.grid[1][1])
      assert.are.equal(SokobanGame.WALL, game.grid[1][6])

      -- Row 2: "#@ $ .#"
      assert.are.equal(SokobanGame.WALL, game.grid[2][1])
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][2])
      assert.are.equal(SokobanGame.FLOOR, game.grid[2][3])
      assert.are.equal(SokobanGame.BOX, game.grid[2][4])
      assert.are.equal(SokobanGame.FLOOR, game.grid[2][5])
      assert.are.equal(SokobanGame.TARGET, game.grid[2][6])
      assert.are.equal(SokobanGame.WALL, game.grid[2][7])

      -- Row 3: "#+ * -#"
      assert.are.equal(SokobanGame.PLR_ON, game.grid[3][2])
      assert.are.equal(SokobanGame.BOX_ON, game.grid[3][4])
      assert.are.equal(SokobanGame.FLOOR, game.grid[3][6]) -- '-' maps to FLOOR

      -- Last parsed player position recorded
      assert.are.equal(3, game.player_r)
      assert.are.equal(2, game.player_c)
      assert.are.equal(0, game.moves)
      assert.are.equal(0, game.pushes)
    end)
  end)

  describe("Query helpers: box counts and solution check", function()
    it("should calculate box_count, boxes_on_target, and is_solved", function()
      local xsb = [[
#######
#@ $ .#
#  * .#
#######
]]
      local game = SokobanGame.from_xsb(xsb)
      assert.are.equal(2, game:box_count())
      assert.are.equal(1, game:boxes_on_target())
      assert.is_false(game:is_solved())

      -- Push the unplaced box onto target
      game.grid[2][4] = SokobanGame.FLOOR
      game.grid[2][6] = SokobanGame.BOX_ON
      assert.are.equal(2, game:box_count())
      assert.are.equal(2, game:boxes_on_target())
      assert.is_true(game:is_solved())
    end)
  end)

  describe("Player movement without box push", function()
    it("should reject moves into walls or out of bounds", function()
      local xsb = [[
#####
# @ #
#####
]]
      local game = SokobanGame.from_xsb(xsb)
      -- Move up into wall
      assert.is_false(game:move(-1, 0))
      -- Move out of bounds directly
      assert.is_false(game:move(-10, 0))
      assert.are.equal(2, game.player_r)
      assert.are.equal(3, game.player_c)
      assert.are.equal(0, game.moves)
    end)

    it("should update player cell, vacate previous cell, and handle targets", function()
      local xsb = [[
#######
# @ . #
#######
]]
      local game = SokobanGame.from_xsb(xsb)
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][3])

      -- Move right to empty floor
      assert.is_true(game:move(0, 1))
      assert.are.equal(2, game.player_r)
      assert.are.equal(4, game.player_c)
      assert.are.equal(SokobanGame.FLOOR, game.grid[2][3])
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][4])
      assert.are.equal(1, game.moves)
      assert.are.equal(0, game.pushes)

      -- Move right onto target
      assert.is_true(game:move(0, 1))
      assert.are.equal(SokobanGame.PLR_ON, game.grid[2][5])
      assert.are.equal(SokobanGame.FLOOR, game.grid[2][4])

      -- Move right off target
      assert.is_true(game:move(0, 1))
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][6])
      assert.are.equal(SokobanGame.TARGET, game.grid[2][5]) -- target restored
    end)
  end)

  describe("Pushing boxes", function()
    it("should push boxes onto floors and targets", function()
      local xsb = [[
#########
# @ $ . #
#########
]]
      local game = SokobanGame.from_xsb(xsb)
      -- Push box right onto target
      -- Player at (2, 3), box at (2, 5), target at (2, 7)
      assert.is_true(game:move(0, 1)) -- step to (2, 4)
      assert.is_true(game:move(0, 1)) -- push box from (2, 5) to (2, 6)

      assert.are.equal(2, game.moves)
      assert.are.equal(1, game.pushes)
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][5])
      assert.are.equal(SokobanGame.BOX, game.grid[2][6])

      -- Push box again onto target at (2, 7)
      assert.is_true(game:move(0, 1))
      assert.are.equal(3, game.moves)
      assert.are.equal(2, game.pushes)
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][6])
      assert.are.equal(SokobanGame.BOX_ON, game.grid[2][7])
      assert.is_true(game:is_solved())
    end)

    it("should reject pushing box into walls or another box", function()
      local xsb = [[
#######
# @$$ #
#######
]]
      local game = SokobanGame.from_xsb(xsb)
      -- Pushing box into another box
      assert.is_false(game:move(0, 1))
      assert.are.equal(0, game.moves)
      assert.are.equal(0, game.pushes)

      -- Pushing box directly into wall
      local xsb_wall = [[
#####
# @$#
#####
]]
      local game_wall = SokobanGame.from_xsb(xsb_wall)
      assert.is_false(game_wall:move(0, 1))
      assert.are.equal(0, game_wall.moves)
    end)
  end)

  describe("Undo and history cap", function()
    it("should undo moves and pushes restoring complete board state", function()
      local xsb = [[
#######
# @$  #
#######
]]
      local game = SokobanGame.from_xsb(xsb)
      assert.is_false(game:undo())

      game:move(0, 1) -- push box from (2, 4) to (2, 5)
      assert.are.equal(1, game.moves)
      assert.are.equal(1, game.pushes)
      assert.are.equal(4, game.player_c)

      assert.is_true(game:undo())
      assert.are.equal(0, game.moves)
      assert.are.equal(0, game.pushes)
      assert.are.equal(3, game.player_c)
      assert.are.equal(SokobanGame.PLAYER, game.grid[2][3])
      assert.are.equal(SokobanGame.BOX, game.grid[2][4])
      assert.are.equal(SokobanGame.FLOOR, game.grid[2][5])
    end)

    it("should cap undo history at 500 items", function()
      local xsb = [[
#####
# @ #
#   #
#####
]]
      local game = SokobanGame.from_xsb(xsb)
      for _ = 1, 520 do
        game:move(1, 0)
        game:move(-1, 0)
      end
      assert.are.equal(500, #game.history)
    end)
  end)
end)
