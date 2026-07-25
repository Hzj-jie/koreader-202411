describe("Checkers main plugin module", function()
  local Checkers

  setup(function()
    require("commonrequire")
    Checkers = require("plugins/checkers.koplugin/main")
  end)

  it("should initialize Checkers plugin instance", function()
    local plugin = Checkers:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/checkers.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
