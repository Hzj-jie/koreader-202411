describe("ScoreBoardWidget widget", function()
  local ScoreBoardWidget

  setup(function()
    require("commonrequire")
    ScoreBoardWidget = require("plugins/game2048.koplugin/ui/widget/scoreboardwidget")
  end)

  it("should initialize ScoreBoardWidget", function()
    local widget = ScoreBoardWidget:new()
    assert.is_table(widget)
  end)
end)
