describe("FindKeyboard helper module", function()
  local FindKeyboard

  setup(function()
    require("commonrequire")
    FindKeyboard = require("plugins/externalkeyboard.koplugin/find-keyboard")
  end)

  it("should expose find keyboard helper functions", function()
    assert.is_table(FindKeyboard)
  end)
end)
