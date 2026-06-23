describe("Solitaire game engine unit tests", function()
  local Game

  setup(function()
    require("commonrequire")
    package.unloadAll()
    Game = dofile("plugins/solitaire.koplugin/game.lua")
  end)

  teardown(function()
    package.unloadAll()
  end)

  it("should initialize a new game correctly", function()
    local g = Game:new()
    assert.is_not_nil(g)
    assert.are.equal(0, #g.stock)
    assert.are.equal(0, #g.waste)
    assert.are.equal(4, #g.foundations)
    assert.are.equal(7, #g.tableau)
    assert.are.equal(0, g.moves)
    assert.are.equal(0, g.score)
  end)

  it("should deal the deck and set up piles", function()
    local g = Game:new()
    g:deal()

    -- Verify cards count
    -- Stock: 52 - sum(1..7) = 52 - 28 = 24 cards
    assert.are.equal(24, #g.stock)
    assert.are.equal(0, #g.waste)

    -- Tableau: pile i has i cards, and only the top one is face up
    for i = 1, 7 do
      assert.are.equal(i, #g.tableau[i])
      for j = 1, i - 1 do
        assert.False(g.tableau[i][j].face_up)
      end
      assert.True(g.tableau[i][i].face_up)
    end

    -- Foundations: empty
    for i = 1, 4 do
      assert.are.equal(0, #g.foundations[i])
    end
  end)

  it("should draw from stock to waste", function()
    local g = Game:new()
    g:deal()

    -- Draw one mode
    g:setDrawMode(1)
    assert.are.equal(24, #g.stock)
    assert.are.equal(0, #g.waste)

    -- Draw 1 card
    local success = g:drawFromStock()
    assert.True(success)
    assert.are.equal(23, #g.stock)
    assert.are.equal(1, #g.waste)
    assert.True(g.waste[1].face_up)

    -- Draw all remaining cards
    for i = 1, 23 do
      g:drawFromStock()
    end
    assert.are.equal(0, #g.stock)
    assert.are.equal(24, #g.waste)

    -- Drawing when stock is empty should recycle waste
    success = g:drawFromStock()
    assert.True(success)
    assert.are.equal(24, #g.stock)
    assert.are.equal(0, #g.waste)
    -- All recycled stock cards should be face down
    for _, card in ipairs(g.stock) do
      assert.False(card.face_up)
    end
  end)

  it(
    "should check tableau placement rules (alternating color, decreasing rank)",
    function()
      local g = Game:new()

      -- Red King (hearts, index 1)
      local red_king = { suit = 1, rank = 13, face_up = true }
      -- Black Queen (spades, index 4)
      local black_queen = { suit = 4, rank = 12, face_up = true }
      -- Red Queen (diamonds, index 2)
      local red_queen = { suit = 2, rank = 12, face_up = true }
      -- Black Jack (clubs, index 3)
      local black_jack = { suit = 3, rank = 11, face_up = true }

      -- Place Black Queen on Red King: should be valid
      g.tableau[1] = { red_king }
      assert.True(g:canPlaceOnTableau(black_queen, g.tableau[1]))

      -- Place Red Queen on Red King: invalid (same color)
      assert.False(g:canPlaceOnTableau(red_queen, g.tableau[1]))

      -- Place Black Jack on Black Queen: invalid (same color)
      g.tableau[2] = { black_queen }
      assert.False(g:canPlaceOnTableau(black_jack, g.tableau[2]))

      -- Place Black Jack on Red Queen: valid
      g.tableau[3] = { red_queen }
      assert.True(g:canPlaceOnTableau(black_jack, g.tableau[3]))

      -- Place King on an empty tableau: valid
      g.tableau[4] = {}
      assert.True(g:canPlaceOnTableau(red_king, g.tableau[4]))

      -- Place Queen on an empty tableau: invalid (only Kings on empty tableau)
      assert.False(g:canPlaceOnTableau(red_queen, g.tableau[4]))
    end
  )

  it(
    "should check foundation placement rules (same suit, increasing rank starting with Ace)",
    function()
      local g = Game:new()

      -- Hearts Ace
      local hearts_ace = { suit = 1, rank = 1, face_up = true }
      -- Hearts 2
      local hearts_two = { suit = 1, rank = 2, face_up = true }
      -- Diamonds Ace
      local diamonds_ace = { suit = 2, rank = 1, face_up = true }

      -- Place Hearts Ace on empty foundation 1: valid
      assert.True(g:canPlaceOnFoundation(hearts_ace, 1))

      -- Place Hearts 2 on empty foundation 1: invalid (must start with A)
      assert.False(g:canPlaceOnFoundation(hearts_two, 1))

      -- Set foundation 1 to Hearts Ace
      g.foundations[1] = { hearts_ace }

      -- Place Hearts 2 on foundation 1: valid
      assert.True(g:canPlaceOnFoundation(hearts_two, 1))

      -- Place Diamonds Ace on foundation 1: invalid (different suit, wrong rank)
      assert.False(g:canPlaceOnFoundation(diamonds_ace, 1))
    end
  )

  it("should support serialization to and from save data", function()
    local g1 = Game:new()
    g1:deal()
    g1:drawFromStock()
    g1.score = 150
    g1.moves = 10

    local data = g1:toSaveData()
    assert.is_not_nil(data)

    local g2 = Game:new()
    local loaded = g2:fromSaveData(data)
    assert.True(loaded)

    assert.are.equal(g1.score, g2.score)
    assert.are.equal(g1.moves, g2.moves)
    assert.are.equal(#g1.stock, #g2.stock)
    assert.are.equal(#g1.waste, #g2.waste)

    for i = 1, 7 do
      assert.are.equal(#g1.tableau[i], #g2.tableau[i])
    end
    for i = 1, 4 do
      assert.are.equal(#g1.foundations[i], #g2.foundations[i])
    end
  end)
end)
