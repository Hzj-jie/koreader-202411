describe("OPDSPSE module", function()
  local OPDSPSE

  setup(function()
    require("commonrequire")
    OPDSPSE = require("plugins/opds.koplugin/opdspse")
  end)

  it("should initialize OPDSPSE module", function()
    assert.is_table(OPDSPSE)
  end)
end)
