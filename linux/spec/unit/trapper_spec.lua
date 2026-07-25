describe("Trapper module", function()
  local Trapper

  setup(function()
    require("commonrequire")
    Trapper = require("ui/trapper")
  end)

  it("should initialize Trapper module", function()
    assert.is_table(Trapper)
    assert.is_function(Trapper.wrap)
  end)
end)
