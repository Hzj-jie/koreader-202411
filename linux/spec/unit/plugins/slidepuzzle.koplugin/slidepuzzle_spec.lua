describe("Slide Puzzle game logic unit tests", function()
  local Game

  setup(function()
    require("commonrequire")
    package.unloadAll()
    Game = dofile("plugins/slidepuzzle.koplugin/slidepuzzle_game.lua")
  end)

  teardown(function()
    package.unloadAll()
  end)

  it("should initialize a new game of correct size", function()
    local g = Game:new(4)
    assert.are.equal(4, g.size)
    assert.are.equal(4, g.empty_r)
    assert.are.equal(4, g.empty_c)
    assert.are.equal(0, g.moves)
    assert.True(g.won)

    -- Test bounds capping
    local g_min = Game:new(1)
    assert.are.equal(Game.getMinSize(), g_min.size)
    local g_max = Game:new(10)
    assert.are.equal(Game.getMaxSize(), g_max.size)
  end)

  it("should initialize tiles in solved order", function()
    local g = Game:new(3)
    -- Expected grid for 3x3:
    -- 1 2 3
    -- 4 5 6
    -- 7 8 0
    assert.are.equal(1, g.grid[1][1])
    assert.are.equal(2, g.grid[1][2])
    assert.are.equal(3, g.grid[1][3])
    assert.are.equal(4, g.grid[2][1])
    assert.are.equal(5, g.grid[2][2])
    assert.are.equal(6, g.grid[2][3])
    assert.are.equal(7, g.grid[3][1])
    assert.are.equal(8, g.grid[3][2])
    assert.are.equal(0, g.grid[3][3])
    assert.True(g:checkSolved())
  end)

  it("should allow valid tap-style moves", function()
    local g = Game:new(3) -- empty cell is at (3,3)
    -- Try moving tile at (2,3) (value 6) down into (3,3)
    -- Before move:
    -- 7 8 0 (row 3)
    -- 4 5 6 (row 2)
    g.won = false -- must mark as playing first
    local ok, prev_r, prev_c = g:moveTileAt(2, 3)
    assert.True(ok)
    assert.are.equal(3, prev_r)
    assert.are.equal(3, prev_c)
    assert.are.equal(2, g.empty_r)
    assert.are.equal(3, g.empty_c)
    assert.are.equal(1, g.moves)

    -- Grid should be:
    -- 1 2 3
    -- 4 5 0
    -- 7 8 6
    assert.are.equal(0, g.grid[2][3])
    assert.are.equal(6, g.grid[3][3])
  end)

  it("should ignore invalid tap-style moves", function()
    local g = Game:new(3) -- empty cell is at (3,3)
    g.won = false
    -- Try moving tile at (1,1) (value 1) - not adjacent to (3,3)
    assert.False(g:moveTileAt(1, 1))
    assert.are.equal(3, g.empty_r)
    assert.are.equal(3, g.empty_c)
    assert.are.equal(0, g.moves)
  end)

  it("should allow swipe-style moves", function()
    local g = Game:new(3) -- empty cell is at (3,3)
    g.won = false
    -- Swiping "up" should move the tile below the empty cell (doesn't exist)
    assert.False(g:slide("up"))

    -- Swiping "down" should move the tile above the empty cell (2,3) down
    local ok = g:slide("down")
    assert.True(ok)
    assert.are.equal(2, g.empty_r)
    assert.are.equal(3, g.empty_c)

    -- Now empty cell is at (2,3)
    -- Swiping "left" should move the tile to the right of empty cell (doesn't exist)
    assert.False(g:slide("left"))

    -- Swiping "right" should move the tile to the left of empty cell (2,2) right
    assert.True(g:slide("right"))
    assert.are.equal(2, g.empty_r)
    assert.are.equal(2, g.empty_c)
  end)

  it("should scramble board on shuffle and verify it is not solved", function()
    local g = Game:new(3)
    g:shuffle()
    assert.False(g:checkSolved())
    assert.False(g.won)
    assert.are.equal(0, g.moves)
  end)
end)
