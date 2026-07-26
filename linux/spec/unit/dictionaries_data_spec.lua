describe("Dictionaries data module", function()
  local Dictionaries

  setup(function()
    require("commonrequire")
    Dictionaries = require("ui/data/dictionaries")
  end)

  it("should return dictionaries list/table", function()
    assert.is_table(Dictionaries)
  end)
end)
