describe("Wallabag plugin", function()
  local Wallabag

  setup(function()
    require("commonrequire")
    Wallabag = require("plugins/wallabag.koplugin/main")
  end)

  it("should initialize Wallabag plugin class", function()
    assert.is_table(Wallabag)
  end)
end)
