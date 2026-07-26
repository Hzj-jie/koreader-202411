describe("OPDSCatalog module", function()
  local OPDSCatalog

  setup(function()
    require("commonrequire")
    OPDSCatalog = require("plugins/opds.koplugin/opdscatalog")
  end)

  it("should initialize OPDSCatalog", function()
    local catalog = OPDSCatalog:new()
    assert.is_table(catalog)
  end)
end)
