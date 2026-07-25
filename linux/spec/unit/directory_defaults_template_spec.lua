describe("DirectoryDefaultsTemplate module", function()
  local Template

  setup(function()
    require("commonrequire")
    Template = require("plugins/docsettingtweak.koplugin/directory_defaults_template")
  end)

  it("should return directory defaults template table", function()
    assert.is_table(Template)
  end)
end)
