describe("Sokoban game logic unit tests", function()
  local Game

  setup(function()
    require("commonrequire")
    package.unloadAll()
    Game = dofile("plugins/sokoban.koplugin/sokoban_game.lua")
  end)

  teardown(function()
    package.unloadAll()
  end)

  local function buildSimpleLevel()
    local level = [[
####
# .#
#  ###
#*@  #
#  $ #
#  ###
####]]
    return Game.from_xsb(level)
  end

  it("should parse XSB levels correctly", function()
    local g = buildSimpleLevel()
    assert.are.equal(7, g.rows)
    assert.are.equal(6, g.cols)
    assert.are.equal(4, g.player_r)
    assert.are.equal(3, g.player_c)
    assert.are.equal(2, g:box_count())
    assert.are.equal(1, g:boxes_on_target())
    assert.False(g:is_solved())
  end)

  it("should allow player to move to empty floor and targets", function()
    local g = buildSimpleLevel()
    -- Move up (dr=-1, dc=0) to empty floor at (3,3)
    assert.True(g:move(-1, 0))
    assert.are.equal(3, g.player_r)
    assert.are.equal(3, g.player_c)
    assert.are.equal(1, g.moves)
    assert.are.equal(0, g.pushes)

    -- Move left (dr=0, dc=-1) to box on target (*) at (3,2) -> wait, (3,2) is floor, (4,2) is BOX_ON (*)
    -- Player is currently at (3,3). Left is (3,2).
    assert.True(g:move(0, -1))
    assert.are.equal(3, g.player_r)
    assert.are.equal(2, g.player_c)
  end)

  it("should not allow player to move into walls", function()
    local g = buildSimpleLevel()
    -- Move up to (3,3)
    assert.True(g:move(-1, 0))
    -- Try to move right to wall at (3,4)
    assert.False(g:move(0, 1))
    assert.are.equal(3, g.player_r)
    assert.are.equal(3, g.player_c)
  end)

  it("should allow player to push a box onto empty floor", function()
    local g = buildSimpleLevel()
    -- Move down to (5,3)
    assert.True(g:move(1, 0))
    assert.are.equal(5, g.player_r)
    assert.are.equal(3, g.player_c)
    -- Now right (0, 1) is box ($) at (5,4). Behind it is empty space (5,5).
    assert.True(g:move(0, 1))
    assert.are.equal(5, g.player_r)
    assert.are.equal(4, g.player_c)
    assert.are.equal(2, g.moves)
    assert.are.equal(1, g.pushes)
    -- Check old player cell is floor, current is player, box is at target
    assert.are.equal(Game.FLOOR, g.grid[5][3])
    assert.are.equal(Game.PLAYER, g.grid[5][4])
    assert.are.equal(Game.BOX, g.grid[5][5])
  end)

  it("should not allow pushing two boxes or pushing a box into a wall", function()
    -- Construct a level with two adjacent boxes:
    -- @ $ $ .
    local level = "####\n#@$$.#\n####"
    local g = Game.from_xsb(level)
    assert.are.equal(2, g.player_r)
    assert.are.equal(2, g.player_c)
    -- Try to push right (0,1): should fail because two boxes ($ at 2,3 and $ at 2,4)
    assert.False(g:move(0, 1))

    -- Try to push a box into a wall:
    -- @ $ #
    local level2 = "####\n#@$#\n####"
    local g2 = Game.from_xsb(level2)
    assert.False(g2:move(0, 1))
  end)

  it("should support undoing moves and pushes", function()
    local g = buildSimpleLevel()
    local start_r, start_c = g.player_r, g.player_c
    -- Move up
    assert.True(g:move(-1, 0))
    -- Undo
    assert.True(g:undo())
    assert.are.equal(start_r, g.player_r)
    assert.are.equal(start_c, g.player_c)
    assert.are.equal(0, g.moves)

    -- Now move to (5,3) and push box right
    g:move(1, 0)
    local before_push_r, before_push_c = g.player_r, g.player_c
    local box_start_val = g.grid[5][4]
    local behind_start_val = g.grid[5][5]
    assert.True(g:move(0, 1)) -- pushes box
    assert.are.equal(1, g.pushes)

    -- Undo push
    assert.True(g:undo())
    assert.are.equal(before_push_r, g.player_r)
    assert.are.equal(before_push_c, g.player_c)
    assert.are.equal(box_start_val, g.grid[5][4])
    assert.are.equal(behind_start_val, g.grid[5][5])
    assert.are.equal(0, g.pushes)
  end)

  it("should detect solved state", function()
    -- Simple level with one box and one target
    -- @ $ .
    local level = "#####\n#@$.#\n#####"
    local g = Game.from_xsb(level)
    assert.False(g:is_solved())
    assert.True(g:move(0, 1)) -- push box onto target
    assert.True(g:is_solved())
  end)
end)
