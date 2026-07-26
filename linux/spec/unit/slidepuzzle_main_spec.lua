describe("SlidePuzzle main plugin module", function()
  local SlidePuzzle

  setup(function()
    require("commonrequire")
    SlidePuzzle = require("plugins/slidepuzzle.koplugin/main")
  end)

  it("should initialize SlidePuzzle plugin instance", function()
    local plugin = SlidePuzzle:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/slidepuzzle.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
