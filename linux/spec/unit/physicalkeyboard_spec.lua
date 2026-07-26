describe("PhysicalKeyboard widget", function()
  local PhysicalKeyboard

  setup(function()
    require("commonrequire")
    PhysicalKeyboard = require("ui/widget/physicalkeyboard")
  end)

  it("should initialize physical keyboard event listener", function()
    local pk = PhysicalKeyboard:new({
      inputbox = { input_type = "string" },
    })
    assert.is_table(pk)
  end)
end)
