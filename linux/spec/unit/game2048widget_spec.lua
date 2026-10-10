describe("Game2048Widget widget", function()
  local Game2048Widget, Blitbuffer, UIManager

  setup(function()
    require("commonrequire")
    Blitbuffer = require("ffi/blitbuffer")
    UIManager = require("ui/uimanager")
    Game2048Widget =
      require("plugins/game2048.koplugin/ui/widget/game2048widget")
  end)

  local orig_scheduleIn, orig_unschedule, orig_setDirty
  local scheduled_calls, dirty_calls

  before_each(function()
    scheduled_calls = {}
    dirty_calls = {}
    orig_scheduleIn = UIManager.scheduleIn
    orig_unschedule = UIManager.unschedule
    orig_setDirty = UIManager.setDirty

    UIManager.scheduleIn = function(_, delay, callback, arg)
      table.insert(scheduled_calls, { delay = delay, callback = callback, arg = arg })
    end
    UIManager.unschedule = function() end
    UIManager.setDirty = function(_, target, mode, dimen)
      table.insert(dirty_calls, { target = target, mode = mode, dimen = dimen })
    end
  end)

  after_each(function()
    UIManager.scheduleIn = orig_scheduleIn
    UIManager.unschedule = orig_unschedule
    UIManager.setDirty = orig_setDirty
  end)

  describe("Initialization & setNumbers", function()
    it("should initialize default 4x4 numbers and geometry", function()
      local widget = Game2048Widget:new({
        width = 400,
      })
      assert.is_table(widget)
      assert.are.equal(400, widget.width)
      assert.are.equal(400, widget.dimen.w)
      assert.are.equal(400, widget.dimen.h)
      assert.are.equal(16, #widget.numbers)
      assert.are.equal(4, widget._size)
      assert.is_not_nil(widget._tile_side)
    end)

    it("should update numbers for allowed lengths and ignore invalid lengths", function()
      local widget = Game2048Widget:new({ width = 400 })

      -- 3x3 board (9 elements)
      local numbers_9 = { 0, 0, 0, 0, 1, 0, 0, 0, 0 }
      widget:setNumbers(numbers_9)
      assert.are.equal(9, #widget.numbers)
      assert.are.equal(3, widget._size)

      -- 2x2 board (4 elements)
      local numbers_4 = { 1, 2, 3, 4 }
      widget:setNumbers(numbers_4)
      assert.are.equal(4, #widget.numbers)
      assert.are.equal(2, widget._size)

      -- 5x5 board (25 elements)
      local numbers_25 = {}
      for i = 1, 25 do
        numbers_25[i] = 0
      end
      widget:setNumbers(numbers_25)
      assert.are.equal(25, #widget.numbers)
      assert.are.equal(5, widget._size)

      -- Invalid length (e.g. 5 or 10 elements) must be ignored
      widget:setNumbers({ 1, 2, 3, 4, 5 })
      assert.are.equal(25, #widget.numbers)
      assert.are.equal(5, widget._size)
    end)

    it("should handle animate_new_tile and uncover hidden tile", function()
      local widget = Game2048Widget:new({ width = 400, new_tile_delay = 0.1 })
      local numbers = { 0, 0, 0, 1 }
      widget:setNumbers(numbers, 4)

      assert.are.equal(4, widget._hidden_tile_index)
      assert.are.equal(1, #scheduled_calls)
      assert.are.equal(0.1, scheduled_calls[1].delay)

      -- Uncover hidden tile
      widget:_uncoverHiddenTile()
      assert.are.equal(0, widget._hidden_tile_index)
    end)
  end)

  describe("Palette, colors, and painting", function()
    it("should update palette and return appropriate tile colors", function()
      local widget = Game2048Widget:new({ width = 400 })
      local dummy_palette = {
        Blitbuffer.COLOR_WHITE,
        Blitbuffer.COLOR_BLACK,
      }
      widget:setPalette(dummy_palette)
      assert.are.equal(dummy_palette, widget.palette)

      local bg, fg = widget:_getTileColors(1)
      assert.are.equal(Blitbuffer.COLOR_WHITE, bg)
      assert.are.equal(Blitbuffer.COLOR_BLACK, fg)
    end)

    it("should paint to blitbuffer in unfocused, focused, and active states with tiles", function()
      local widget = Game2048Widget:new({ width = 400 })
      local numbers = {}
      for i = 1, 16 do
        numbers[i] = 0
      end
      numbers[1] = 1 -- 2
      numbers[2] = 2 -- 4
      numbers[3] = 11 -- 2048
      numbers[4] = 28 -- > MAX_VALUE (fallback ∞)
      widget:setNumbers(numbers)

      local bb = Blitbuffer.new(400, 400)

      -- Unfocused paint
      widget._has_focus = false
      widget._is_active = false
      widget:paintTo(bb, 0, 0)
      assert.are.equal(0, widget.dimen.x)
      assert.are.equal(0, widget.dimen.y)

      -- Focused paint
      widget._has_focus = true
      widget:paintTo(bb, 0, 0)

      -- Active paint
      widget._is_active = true
      widget:paintTo(bb, 0, 0)
    end)
  end)

  describe("Focus, active state, and move handling", function()
    it("should toggle active state on tap when focused", function()
      local widget = Game2048Widget:new({ width = 400 })
      assert.is_false(widget._has_focus)
      assert.is_false(widget._is_active)

      -- Tap when not focused does not activate
      assert.is_false(widget:onTapGame2048())
      assert.is_false(widget._is_active)

      -- Focus widget
      widget:onFocus()
      assert.is_true(widget._has_focus)

      -- Tap toggles active
      assert.is_false(widget:onTapGame2048())
      assert.is_true(widget._is_active)

      assert.is_false(widget:onTapGame2048())
      assert.is_false(widget._is_active)

      -- Unfocus resets active
      widget._is_active = true
      widget:onUnfocus()
      assert.is_false(widget._has_focus)
      assert.is_false(widget._is_active)
    end)

    it("should handle onGame2048Move only when active", function()
      local moved_dir = nil
      local widget = Game2048Widget:new({
        width = 400,
        move_handler = function(dir)
          moved_dir = dir
        end,
      })

      -- Inactive: ignores move
      widget:setActive(false)
      assert.is_false(widget:onGame2048Move("up"))
      assert.is_nil(moved_dir)

      -- Active: triggers move_handler
      widget:setActive(true)
      assert.is_true(widget:onGame2048Move("up"))
      assert.are.equal("up", moved_dir)

      assert.is_true(widget:onGame2048Move("left"))
      assert.are.equal("left", moved_dir)
    end)

    it("should map onSwipe directions and trigger move_handler", function()
      local moved_dir = nil
      local widget = Game2048Widget:new({
        width = 400,
        move_handler = function(dir)
          moved_dir = dir
        end,
      })

      assert.is_true(widget:onSwipe(nil, { direction = "west" }))
      assert.are.equal("left", moved_dir)

      assert.is_true(widget:onSwipe(nil, { direction = "east" }))
      assert.are.equal("right", moved_dir)

      assert.is_true(widget:onSwipe(nil, { direction = "north" }))
      assert.are.equal("up", moved_dir)

      assert.is_true(widget:onSwipe(nil, { direction = "south" }))
      assert.are.equal("down", moved_dir)

      assert.is_false(widget:onSwipe(nil, { direction = "unknown" }))
    end)
  end)
end)
