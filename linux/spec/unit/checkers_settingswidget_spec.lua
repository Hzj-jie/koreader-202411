describe("CheckersSettingsWidget widget", function()
  local SettingsWidget, InputDialog, UIManager

  setup(function()
    require("commonrequire")
    InputDialog = require("ui/widget/inputdialog")
    UIManager = require("ui/uimanager")
    SettingsWidget = require("plugins/checkers.koplugin/settingswidget")
  end)

  it(
    "should initialize SettingsWidget and validate constructor options",
    function()
      assert.has_error(function()
        SettingsWidget:new({
          onApply = function() end,
        })
      end, "parent is required")

      assert.has_error(function()
        SettingsWidget:new({
          parent = {
            human = { true, false },
            ai_depth = 5,
          },
        })
      end, "onApply callback is required")

      local widget = SettingsWidget:new({
        parent = {
          human = { true, false },
          ai_depth = 5,
        },
        onApply = function() end,
      })

      assert.is_table(widget)
      assert.is_table(widget.changes)
      assert.is_true(widget.changes.human[1])
      assert.is_false(widget.changes.human[2])
      assert.are.equal(5, widget.changes.ai_depth)
    end
  )

  it("should apply changes and close dialog on applyAndClose", function()
    local applied_changes = nil
    local closed_dialog = nil
    local orig_close = UIManager.close
    UIManager.close = function(_, dlg)
      closed_dialog = dlg
    end
    finally(function()
      UIManager.close = orig_close
    end)

    local dummy_dlg = {}
    local widget = SettingsWidget:new({
      parent = {
        human = { true, true },
        ai_depth = 3,
      },
      onApply = function(changes)
        applied_changes = changes
      end,
    })
    widget.dialog = dummy_dlg

    widget:applyAndClose()

    assert.are.equal(widget.changes, applied_changes)
    assert.are.equal(dummy_dlg, closed_dialog)
  end)

  it(
    "should configure element width and assemble dialog sections on show",
    function()
      local shown_widget = nil
      local orig_show = UIManager.show
      UIManager.show = function(_, dlg)
        shown_widget = dlg
      end
      finally(function()
        UIManager.show = orig_show
      end)

      local widget = SettingsWidget:new({
        parent = {
          human = { true, false },
          ai_depth = 5,
        },
        onApply = function() end,
      })

      widget:show()

      assert.is_not_nil(widget.dialog)
      assert.are.equal(shown_widget, widget.dialog)
      assert.are.equal(
        math.floor(widget.dialog.width * 0.8),
        widget.dialog.element_width
      )
      assert.is_not_nil(widget.playerSection)
      assert.is_not_nil(widget.difficultySection)
      assert.is_not_nil(widget.difficultyProgress)
      assert.is_not_nil(widget.difficultyLabel)
    end
  )

  it(
    "should update difficulty changes when progress callback is invoked",
    function()
      local orig_show = UIManager.show
      local orig_set_dirty = UIManager.setDirty
      UIManager.show = function() end
      UIManager.setDirty = function() end
      finally(function()
        UIManager.show = orig_show
        UIManager.setDirty = orig_set_dirty
      end)

      local widget = SettingsWidget:new({
        parent = {
          human = { true, false },
          ai_depth = 3,
        },
        onApply = function() end,
      })

      widget:show()

      assert.are.equal(3, widget.changes.ai_depth)
      assert.are.equal(1, widget.difficultyProgress.position)

      widget.difficultyProgress.callback(3)
      assert.are.equal(7, widget.changes.ai_depth)
      assert.are.equal(3, widget.difficultyProgress.position)

      widget.difficultyProgress.callback("invalid")
      assert.are.equal(7, widget.changes.ai_depth)
    end
  )

  it(
    "does not pass dismiss_callback to InputDialog for dismiss handling",
    function()
      local captured_args = nil
      local orig_new = InputDialog.new
      InputDialog.new = function(self, args)
        captured_args = args
        return orig_new(self, args)
      end
      local orig_show = UIManager.show
      UIManager.show = function() end
      finally(function()
        InputDialog.new = orig_new
        UIManager.show = orig_show
      end)

      local widget = SettingsWidget:new({
        parent = {
          human = { true, false },
          ai_depth = 5,
        },
        onApply = function() end,
      })

      widget:show()

      assert.is_not_nil(captured_args)
      assert.is_not_nil(captured_args.save_callback)
      assert.is_nil(captured_args.close_callback)
    end
  )
end)
