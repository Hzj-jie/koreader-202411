describe("Sokoban main plugin module", function()
  local Sokoban

  setup(function()
    require("commonrequire")
    Sokoban = require("plugins/sokoban.koplugin/main")
  end)

  it("should initialize Sokoban plugin instance", function()
    local plugin = Sokoban:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/sokoban.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
