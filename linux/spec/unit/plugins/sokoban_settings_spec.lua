describe("Sokoban Settings widget", function()
  local SettingsWidget

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    SettingsWidget = require("plugins/sokoban.koplugin/sokoban_settings")
  end)

  it("should initialize Sokoban SettingsWidget instance", function()
    local widget = SettingsWidget:new({
      level_sets = {
        { name = "Easy", count = 10 },
        { name = "Hard", count = 5 },
      },
      current_set = "Easy",
      current_level = 1,
      furthest_reached = { Easy = 3 },
      best_moves = { Easy = { [1] = 12 } },
    })
    assert.is_table(widget)
    assert.are.equal("Easy", widget.current_set)
    assert.are.equal(1, widget.current_level)
  end)

  it("should handle lifecycle methods onShow, onClose, onTapClose", function()
    local widget = SettingsWidget:new({
      level_sets = {
        { name = "Default", count = 5 },
      },
      current_set = "Default",
      current_level = 1,
    })
    widget:onShow()
    widget:onCloseWidget()
    assert.is_true(widget:onTapClose())
  end)
end)
