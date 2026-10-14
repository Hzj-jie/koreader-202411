describe("Game2048 History module", function()
  local History

  setup(function()
    require("commonrequire")
    History = require("plugins/game2048.koplugin/modules/history")
  end)

  it("should initialize empty History instance", function()
    local h = History:new()
    assert.is_table(h)
    assert.are.equal(10, h.capacity)
    assert.is_true(h:isEmpty())
    assert.is_false(h:canUndo())
    assert.is_false(h:canRedo())
    assert.is_nil(h:current())
  end)

  it("should push items and maintain current", function()
    local h = History:new({ capacity = 5 })
    h:push(10)
    assert.is_false(h:isEmpty())
    assert.are.equal(10, h:current())
    assert.is_false(h:canUndo()) -- position == tail
    assert.is_false(h:canRedo())

    h:push(20)
    assert.are.equal(20, h:current())
    assert.is_true(h:canUndo())
    assert.is_false(h:canRedo())

    h:push(30)
    assert.are.equal(30, h:current())
  end)

  it("should handle undo and redo", function()
    local h = History:new({ capacity = 5 })
    h:push("a")
    h:push("b")
    h:push("c")

    assert.are.equal("c", h:current())
    assert.is_true(h:canUndo())
    assert.is_false(h:canRedo())

    assert.are.equal("b", h:undo())
    assert.are.equal("b", h:current())
    assert.is_true(h:canUndo())
    assert.is_true(h:canRedo())

    assert.are.equal("a", h:undo())
    assert.are.equal("a", h:current())
    assert.is_false(h:canUndo())
    assert.is_true(h:canRedo())

    assert.is_nil(h:undo())

    assert.are.equal("b", h:redo())
    assert.are.equal("b", h:current())

    assert.are.equal("c", h:redo())
    assert.are.equal("c", h:current())
    assert.is_false(h:canRedo())
    assert.is_nil(h:redo())
  end)

  it("should discard redo items when pushing after undo", function()
    local h = History:new({ capacity = 5 })
    h:push("first")
    h:push("second")
    h:push("third")

    assert.are.equal("second", h:undo())
    h:push("alternate")

    assert.are.equal("alternate", h:current())
    assert.is_false(h:canRedo())

    assert.are.equal("second", h:undo())
    assert.are.equal("first", h:undo())
    assert.is_nil(h:undo())
  end)

  it("should handle ring-buffer wraparound when exceeding capacity", function()
    local h = History:new({ capacity = 4 })
    -- Capacity is 4, so buffer can hold at most capacity - 1 = 3 items before overwriting
    h:push(1)
    h:push(2)
    h:push(3)
    h:push(4)
    h:push(5)

    assert.are.equal(5, h:current())
    assert.are.equal(4, h:undo())
    assert.are.equal(3, h:undo())
    -- Oldest item 1 and 2 were dropped when tail moved forward
    assert.is_false(h:canUndo())
  end)

  it("should clear history", function()
    local h = History:new({ capacity = 5 })
    h:push("x")
    h:push("y")
    h:clear()

    assert.is_true(h:isEmpty())
    assert.is_nil(h:current())
    assert.is_false(h:canUndo())
    assert.is_false(h:canRedo())
  end)

  it("should save and read history round-trip", function()
    local h = History:new({ capacity = 5 })
    h:push("item1")
    h:push("item2")
    h:push("item3")
    h:undo()

    local saved = h:save()
    assert.is_table(saved)
    assert.are.equal(3, #saved.history)
    assert.are.equal(2, saved.position)

    local h2 = History:new({ capacity = 5 })
    local ok = h2:read(saved)
    assert.is_true(ok)
    assert.are.equal("item2", h2:current())
    assert.is_true(h2:canUndo())
    assert.is_true(h2:canRedo())
  end)

  it("should handle invalid read input", function()
    local h = History:new()
    assert.is_false(h:read(nil))
    assert.is_false(h:read({}))
    assert.is_false(h:read({ history = { 1, 2 } }))
  end)

  it("should adjust position when reading dump exceeding capacity (fails due to unadjusted dump.position offset bug)", function()
    local h = History:new({ capacity = 5 })
    -- dump has 8 items, capacity is 5.
    -- capacity - 1 = 4 items will be retained.
    -- Dump position is 8 (the last item, value 80).
    local dump = {
      history = { 10, 20, 30, 40, 50, 60, 70, 80 },
      position = 8,
    }

    local ok = h:read(dump)
    assert.is_true(ok)

    -- In truncated history, position must be adjusted to the retained range (1..4)
    -- Expected current() to be 80, but due to bug self._position is 8 and self._history[8] is nil
    assert.are.equal(80, h:current())
  end)
end)
