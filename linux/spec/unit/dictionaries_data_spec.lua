describe("Dictionaries data module", function()
  local Dictionaries

  setup(function()
    require("commonrequire")
    Dictionaries = require("ui/data/dictionaries")
  end)

  it("should return dictionaries list/table with valid structure", function()
    assert.is_table(Dictionaries)
    assert.is_true(#Dictionaries > 10)
    for _, dict in ipairs(Dictionaries) do
      assert.is_string(dict.name)
      assert.is_string(dict.lang_in)
      assert.is_string(dict.lang_out)
      assert.is_number(dict.entries)
      assert.is_string(dict.url)
    end
  end)
end)
