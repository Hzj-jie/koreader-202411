describe("GameBoard module for 2048 game", function()
  local GameBoard

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    GameBoard = require("plugins/game2048.koplugin/modules/gameboard")
  end)

  it("should initialize 2048 board and manage field dimensions", function()
    local board = GameBoard:new()
    assert.are.equal(4, board:getSize())

    board:setSize(3)
    assert.are.equal(3, board:getSize())
    assert.are.equal(9, #board:getField())

    board:reset()
    assert.are.equal(9, #board:getField())
  end)

  it("should copy and restore field grid state", function()
    local board = GameBoard:new()
    board:setSize(4)

    local field = board:getFieldCopy()
    field[1] = 2
    field[2] = 2

    assert.is_true(board:setFieldCopy(field))
    assert.are.equal(2, board:getElement(1, 1))

    local copy_board = board:copy()
    assert.are.equal(2, copy_board:getElement(1, 1))
  end)

  it("should shift tiles left/right/up/down and combine matching numbers", function()
    local board = GameBoard:new()
    board:setSize(4)
    local field = board:getField()

    -- Set top row to [1, 1, 0, 0] (powers of 2 index: 1 + 1 = 2)
    field[1] = 1
    field[2] = 1

    local merged_value = nil
    local shifted = board:shift("left", function(val)
      merged_value = val
    end)

    assert.is_true(shifted)
    assert.are.equal(2, board:getElement(1, 1))
    assert.are.equal(2, merged_value)
  end)

  it("should place new random tile and detect mergeable tiles", function()
    local board = GameBoard:new()
    board:setSize(2)

    local pos, is_full = board:placeNew()
    assert.is_not_nil(pos)
    assert.is_false(is_full)

    -- Fill board with identical tiles to test canMerge
    local field = board:getField()
    field[1], field[2], field[3], field[4] = 2, 2, 2, 2

    assert.is_true(board:canMerge())

    local dump_text = board:dump()
    assert.is_string(dump_text)
    assert.is_true(dump_text:find("2") ~= nil)
  end)
end)
