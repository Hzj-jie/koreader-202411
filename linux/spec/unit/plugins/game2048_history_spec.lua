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

  it("should clear history", function()
    local h = History:new({ capacity = 5 })
    h:push("move1")
    h:clear()
    assert.truthy(h:isEmpty())
  end)
end)
