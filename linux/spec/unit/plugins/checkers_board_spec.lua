describe("Checkers Board module", function()
  local CheckersBoard
  local Game
  local Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    CheckersBoard = require("plugins/checkers.koplugin/board")
    Game = require("plugins/checkers.koplugin/game")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should initialize CheckersBoard and layout 8x8 grid", function()
    local game = Game.new()
    local board = CheckersBoard:new({
      game = game,
      width = 400,
      height = 400,
    })

    assert.is_table(board)
    assert.is_table(board.btable)
    assert.are.equal(board.width, 400)
    assert.are.equal(board.height, 400)
    assert.is_table(board:getSize())
  end)

  it("should handle square selection, hints, and clicks", function()
    local game = Game.new()
    local move_executed = nil
    local board = CheckersBoard:new({
      game = game,
      width = 400,
      height = 400,
      moveCallback = function(from, to)
        move_executed = { from, to }
      end,
    })

    -- Click on light square (nothing happens)
    board:handleClick(0, 0)
    assert.is_nil(board.selected_pos)

    -- Click on a friendly piece (e.g. rank 2, file 1 -> black piece)
    board:handleClick(2, 1)
    assert.is_not_nil(board.selected_pos)
    assert.is_table(board.hint_positions)

    -- Click again on same square (deselects)
    board:handleClick(2, 1)
    assert.is_nil(board.selected_pos)

    -- Select again and click an empty target to move
    board:handleClick(2, 1)
    local from_pos = board.selected_pos
    local moves = game:get_moves_for_piece(from_pos)
    if #moves > 0 then
      local to_pos = moves[1][2]
      -- Find rank, file for to_pos
      for r = 0, 7 do
        for f = 0, 7 do
          -- Dark squares
          if (r + f) % 2 == 1 then
            local p = (r % 2 == 0) and (r * 4 + math.floor((f - 1) / 2) + 1) or (r * 4 + math.floor(f / 2) + 1)
            if p == to_pos then
              board:handleClick(r, f)
              break
            end
          end
        end
      end
    end

    board:updateBoard()
  end)

  it("should render board onto a Blitbuffer", function()
    local game = Game.new()
    local board = CheckersBoard:new({
      game = game,
      width = 400,
      height = 400,
    })

    local bb = Blitbuffer.new(400, 400)
    board:paintTo(bb, 0, 0)
    bb:free()
  end)
end)
