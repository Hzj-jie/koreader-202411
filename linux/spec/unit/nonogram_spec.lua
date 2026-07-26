describe("Nonogram plugin main module", function()
  local Nonogram

  setup(function()
    require("commonrequire")
    Nonogram = require("plugins/nonogram.koplugin/main")
  end)

  it("should initialize Nonogram plugin instance", function()
    local plugin = Nonogram:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/nonogram.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
