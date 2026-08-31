describe("OpenWithDialog widget", function()
  local OpenWithDialog
  local UIManager

  setup(function()
    require("commonrequire")
    OpenWithDialog = require("ui/widget/openwithdialog")
    UIManager = require("ui/uimanager")
  end)

  it("should initialize open with dialog and update check buttons on radio selection", function()
    local dialog = OpenWithDialog:new({
      title = "Open with...",
      file = "sample.pdf",
      radio_buttons = {
        {
          {
            text = "Engine 1 (All enabled)",
            provider = { disable_file = false, disable_type = false },
          },
          {
            text = "Engine 2 (Disabled options)",
            provider = { disable_file = true, disable_type = true },
          },
        },
      },
    })

    assert.is_table(dialog)
    assert.truthy(dialog._check_file_button)
    assert.truthy(dialog._check_global_button)
    assert.is_true(dialog._check_file_button.enabled)
    assert.is_true(dialog._check_global_button.enabled)

    -- Trigger select of Engine 2 (which has disable_file = true, disable_type = true)
    local btn2 = {
      provider = { disable_file = true, disable_type = true },
    }
    dialog.radio_button_table.button_select_callback(btn2)
    assert.is_false(dialog._check_file_button.enabled)
    assert.is_false(dialog._check_global_button.enabled)

    -- Trigger select of Engine 1 (re-enables)
    local btn1 = {
      provider = { disable_file = false, disable_type = false },
    }
    dialog.radio_button_table.button_select_callback(btn1)
    assert.is_true(dialog._check_file_button.enabled)
    assert.is_true(dialog._check_global_button.enabled)
  end)

  it("should mark dirty on close", function()
    local dialog = OpenWithDialog:new({
      file = "sample.pdf",
      radio_buttons = {
        {
          {
            text = "Engine 1",
            provider = { disable_file = false, disable_type = false },
          },
        },
      },
    })

    local dirty_widget = nil
    local dirty_func = nil
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, func)
      dirty_widget = widget
      dirty_func = func
    end

    dialog:onClose()
    assert.is_nil(dirty_widget)
    assert.truthy(dirty_func)
    local mode, region = dirty_func()
    assert.are.equal("ui", mode)
    assert.are.equal(dialog.dialog_frame.dimen, region)

    UIManager.setDirty = orig_setDirty
  end)
end)
