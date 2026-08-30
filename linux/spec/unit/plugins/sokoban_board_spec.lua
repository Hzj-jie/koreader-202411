describe("Sokoban Board widget module", function()
  local Board

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Board = require("plugins/sokoban.koplugin/sokoban_board")
  end)

  it("should initialize board metrics and dimensions", function()
    local mock_game = {
      cols = 5,
      rows = 5,
    }

    local b = Board:new({
      game = mock_game,
      width = 250,
      height = 250,
      icon_dir = "plugins/sokoban.koplugin/icons",
    })
    b:init()

    assert.are.equal(50, b.cell_size)
    assert.are.equal(0, b.offset_x)
    assert.are.equal(0, b.offset_y)
    assert.is_table(b:getSize())
  end)

  it("should handle swipe gestures and update player sprite", function()
    local mock_game = { cols = 5, rows = 5 }
    local last_move = nil

    local b = Board:new({
      game = mock_game,
      width = 250,
      height = 250,
      icon_dir = "plugins/sokoban.koplugin/icons",
      on_swipe_cb = function(dr, dc)
        last_move = { dr, dc }
      end,
    })
    b:init()

    assert.is_true(b:onSwipe({ direction = "east" }))
    assert.are.equal("player_right", b.player_sprite)
    assert.are.same({ 0, 1 }, last_move)

    assert.is_true(b:onSwipe({ direction = "north" }))
    assert.are.equal("player_up", b.player_sprite)
    assert.are.same({ -1, 0 }, last_move)
  end)

  it("should free image cache resources", function()
    local mock_game = { cols = 5, rows = 5 }
    local b = Board:new({
      game = mock_game,
      width = 250,
      height = 250,
      icon_dir = "plugins/sokoban.koplugin/icons",
    })
    b:init()

    local freed = false
    b._img_cache["test"] = {
      free = function()
        freed = true
      end,
    }

    b:freeImages()
    assert.is_true(freed)
    assert.are.same({}, b._img_cache)
  end)
end)
