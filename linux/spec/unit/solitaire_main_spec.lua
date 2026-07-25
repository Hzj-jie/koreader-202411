describe("Solitaire main plugin module", function()
  local Solitaire

  setup(function()
    require("commonrequire")
    Solitaire = require("plugins/solitaire.koplugin/main")
  end)

  it("should initialize Solitaire plugin instance", function()
    local plugin = Solitaire:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
      path = "plugins/solitaire.koplugin",
    })

    assert.is_table(plugin)
  end)
end)
