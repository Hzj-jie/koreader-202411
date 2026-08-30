describe("CheckersSettingsWidget widget", function()
  local SettingsWidget

  setup(function()
    require("commonrequire")
    SettingsWidget = require("plugins/checkers.koplugin/settingswidget")
  end)

  it("should initialize SettingsWidget", function()
    local widget = SettingsWidget:new({
      parent = {
        human = { "white", "black" },
        ai_depth = 2,
      },
      onApply = function() end,
    })

    assert.is_table(widget)
  end)
end)
