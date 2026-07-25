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
end)
