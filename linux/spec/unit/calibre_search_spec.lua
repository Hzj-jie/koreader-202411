describe("Calibre Search module", function()
  local Search

  setup(function()
    require("commonrequire")
    Search = require("plugins/calibre.koplugin/search")
  end)

  it("should initialize Calibre Search module", function()
    assert.is_table(Search)
  end)
end)
