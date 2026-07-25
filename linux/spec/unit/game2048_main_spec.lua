describe("Game2048 plugin main module", function()
  local Game2048

  setup(function()
    require("commonrequire")
    Game2048 = require("plugins/game2048.koplugin/main")
  end)

  it("should initialize Game2048 main plugin instance", function()
    local plugin = Game2048:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/game2048.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
