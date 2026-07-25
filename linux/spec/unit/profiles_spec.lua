describe("Profiles plugin", function()
  local Profiles

  setup(function()
    require("commonrequire")
    Profiles = require("plugins/profiles.koplugin/main")
  end)

  it("should initialize Profiles plugin class", function()
    assert.is_table(Profiles)
  end)
end)
