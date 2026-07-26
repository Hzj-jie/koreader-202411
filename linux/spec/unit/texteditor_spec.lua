describe("TextEditor plugin", function()
  local TextEditor

  setup(function()
    require("commonrequire")
    TextEditor = require("plugins/texteditor.koplugin/main")
  end)

  it("should initialize TextEditor plugin class", function()
    assert.is_table(TextEditor)
  end)
end)
