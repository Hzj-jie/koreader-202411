describe("Checkers main plugin module", function()
  local Checkers
  local UIManager
  local Blitbuffer

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    Checkers = require("plugins/checkers.koplugin/main")
    UIManager = require("ui/uimanager")
    Blitbuffer = require("ffi/blitbuffer")
  end)

  it("should expose Checkers main plugin class and handle settings", function()
    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    instance:init()

    instance.human[1] = true
    instance.human[2] = true
    instance.ai_depth = 3
    instance:saveSettings()
    instance:loadSettings()
    assert.is_true(instance.human[1])
    assert.is_true(instance.human[2])
    assert.are.equal(instance.ai_depth, 3)

    local menu_items = {}
    instance:addToMainMenu(menu_items)
    assert.is_table(menu_items.checkers)
  end)

  it("should manage game lifecycle, layout, moves, AI, undo, and dialogs", function()
    local orig_show = UIManager.show
    local orig_close = UIManager.close
    local orig_schedule = UIManager.scheduleIn
    UIManager.show = function() end
    UIManager.close = function() end
    UIManager.scheduleIn = function(self_uim, delay, fn) fn() end

    local instance = Checkers:new({
      ui = {
        menu = { registerToMainMenu = function() end },
      },
    })
    instance:init()

    -- Start Game
    instance:startGame()
    assert.is_table(instance.game)
    assert.is_table(instance.board)
    assert.is_table(instance.status_bar)

    -- Status updates and turn text
    instance:updateStatus()
    local turn_str = instance:_turn_text()
    assert.is_string(turn_str)
    local mode_str = instance:_mode_label()
    assert.is_string(mode_str)

    -- Moves and AI
    local moves = instance.game:get_possible_moves()
    if #moves > 0 then
      instance.game:move(moves[1][1], moves[1][2])
      instance:onMoveExecuted(moves[1][1], moves[1][2])
    end
    instance:doAIMove()

    -- Undo
    instance:doUndo()

    -- Ask new game and reset
    instance:askNewGame()
    instance:resetGame()

    -- Game over
    instance:showGameOver()

    -- Settings dialog
    instance:openSettings()

    -- Paint to Blitbuffer
    local bb = Blitbuffer.new(instance.full_width or 600, instance.full_height or 800)
    instance:paintTo(bb, 0, 0)
    bb:free()

    -- Handle events
    assert.is_true(instance:onCheckersStart())
    assert.is_true(instance:handleEvent({ handler = "onCheckersStart" }))

    UIManager.show = orig_show
    UIManager.close = orig_close
    UIManager.scheduleIn = orig_schedule
  end)
end)
