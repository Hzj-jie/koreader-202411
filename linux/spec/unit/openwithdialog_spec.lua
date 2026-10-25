describe("OpenWithDialog widget", function()
  local OpenWithDialog

  setup(function()
    require("commonrequire")
    OpenWithDialog = require("ui/widget/openwithdialog")
  end)

  it("should initialize open with dialog", function()
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

    assert.is_table(dialog)
  end)

  it("decrements active_instances on close and allows subsequent InputDialog", function()
    local UIManager = require("ui/uimanager")
    local InputDialog = require("ui/widget/inputdialog")
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

    UIManager:show(dialog)
    UIManager:close(dialog)

    assert.has_no.errors(function()
      local next_dialog = InputDialog:new({
        title = "Next Dialog",
      })
      UIManager:show(next_dialog)
      UIManager:close(next_dialog)
    end)
  end)
end)
