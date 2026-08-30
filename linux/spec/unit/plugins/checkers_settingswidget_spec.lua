describe("Checkers SettingsWidget module", function()
  local SettingsWidget

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SettingsWidget = require("plugins/checkers.koplugin/settingswidget")
  end)

  it("should instantiate SettingsWidget with parent options", function()
    local applied_changes = nil
    local mock_parent = {
      human = { [1] = true, [2] = false },
      ai_depth = 5,
    }

    local widget = SettingsWidget:new({
      parent = mock_parent,
      onApply = function(changes)
        applied_changes = changes
      end,
    })

    assert.is_table(widget)
    assert.are.equal(5, widget.changes.ai_depth)
    assert.is_true(widget.changes.human[1])
    assert.is_false(widget.changes.human[2])

    widget:applyAndClose()
    assert.is_table(applied_changes)
    assert.are.equal(5, applied_changes.ai_depth)
  end)

  it("should show settings dialog and build UI sections", function()
    local mock_parent = {
      human = { [1] = true, [2] = false },
      ai_depth = 3,
    }

    local widget = SettingsWidget:new({
      parent = mock_parent,
      onApply = function() end,
    })

    widget:show()
    assert.is_table(widget.dialog)
    assert.is_table(widget.playerSection)
    assert.is_table(widget.difficultySection)

    if widget.difficultyProgress and widget.difficultyProgress.callback then
      widget.difficultyProgress.callback(2)
      assert.are.equal(5, widget.changes.ai_depth)
    end
  end)
end)
