describe("Game2048 History module", function()
  local History

  setup(function()
    require("commonrequire")
    History = require("plugins/game2048.koplugin/modules/history")
  end)

  it("should push items and manage undo/redo history stack", function()
    local h = History:new({ capacity = 5 })
    assert.truthy(h:isEmpty())
    assert.falsy(h:canUndo())
    assert.falsy(h:canRedo())

    h:push("move1")
    assert.falsy(h:isEmpty())
    assert.are.equal("move1", h:current())
    assert.falsy(h:canUndo())

    h:push("move2")
    assert.truthy(h:canUndo())
    assert.falsy(h:canRedo())

    local item = h:undo()
    assert.are.equal("move1", item)
    assert.truthy(h:canRedo())

    local redo_item = h:redo()
    assert.are.equal("move2", redo_item)
  end)

  it("should clear history and reset pointers", function()
    local h = History:new({ capacity = 5 })
    h:push("move1")
    h:push("move2")
    h:clear()
    assert.truthy(h:isEmpty())
    assert.is_nil(h:current())
    assert.falsy(h:canUndo())
    assert.falsy(h:canRedo())
  end)

  it("should discard redo items when pushing new item after undo", function()
    local h = History:new({ capacity = 5 })
    h:push("move1")
    h:push("move2")
    h:push("move3")

    h:undo()
    assert.are.equal("move2", h:current())
    assert.truthy(h:canRedo())

    h:push("move4")
    assert.are.equal("move4", h:current())
    assert.falsy(h:canRedo())
  end)

  it("should drop oldest items when circular capacity is exceeded", function()
    local h = History:new({ capacity = 4 })
    h:push("a")
    h:push("b")
    h:push("c")
    h:push("d")

    assert.are.equal("d", h:current())
    assert.truthy(h:canUndo())
    assert.are.equal("c", h:undo())
    assert.are.equal("b", h:undo())
    assert.falsy(h:canUndo())
  end)

  it("should save and read normal history accurately", function()
    local h = History:new({ capacity = 5 })
    h:push(10)
    h:push(20)
    h:push(30)
    h:undo()

    local dump = h:save()
    assert.is_table(dump)
    assert.are.equal(2, dump.position)
    assert.are.equal(3, #dump.history)

    local h2 = History:new({ capacity = 5 })
    assert.is_true(h2:read(dump))
    assert.are.equal(20, h2:current())
    assert.truthy(h2:canUndo())
    assert.truthy(h2:canRedo())
  end)

  it(
    "adjusts position within truncated bounds when reading oversized history (fails: oversized position out of bounds)",
    function()
      local h = History:new({ capacity = 5 })
      local dump = {
        history = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
        position = 10,
      }

      assert.is_true(h:read(dump))
      -- Truncated history retains items 7..10 (size 4, head 5).
      -- In modules/history.lua line 149, self._position = dump.position (10),
      -- which points out of bounds (> capacity and > #history), causing current()
      -- to return nil instead of 10.
      assert.is_true(h._position <= h.capacity)
      assert.are.equal(10, h:current())
    end
  )

  it(
    "maintains circular buffer position invariant when reading empty history dump (fails: empty history sets position 0)",
    function()
      local h = History:new({ capacity = 5 })
      local empty_dump = h:save()
      assert.is_table(empty_dump)
      assert.are.equal(0, #empty_dump.history)

      local h2 = History:new({ capacity = 5 })
      assert.is_true(h2:read(empty_dump))
      assert.truthy(h2:isEmpty())

      -- On empty history, _position invariant requires prevPosition(head, capacity),
      -- which is capacity (5), matching History:new and History:clear.
      -- In modules/history.lua line 149, self._position = dump.position (0),
      -- violating the 1-based indexing invariant.
      assert.are.equal(h2.capacity, h2._position)
    end
  )
end)
