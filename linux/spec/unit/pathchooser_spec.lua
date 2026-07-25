describe("PathChooser widget", function()
  local PathChooser

  setup(function()
    require("commonrequire")
    PathChooser = require("ui/widget/pathchooser")
  end)

  it("should initialize PathChooser class", function()
    assert.is_table(PathChooser)
    assert.is_function(PathChooser.new)
  end)
end)
