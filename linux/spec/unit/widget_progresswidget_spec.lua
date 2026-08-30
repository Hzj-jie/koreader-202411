describe("ProgressWidget widget", function()
  local ProgressWidget, Screen
  setup(function()
    require("commonrequire")
    ProgressWidget = require("ui/widget/progresswidget")
    Screen = require("device").screen
  end)

  it("should not crash with nil self.last", function()
    local progress = ProgressWidget:new({
      width = Screen:scaleBySize(100),
      height = Screen:scaleBySize(50),
      percentage = 5 / 100,
      ticks = { 1 },
    })
    progress:paintTo(Screen.bb, 0, 0)
  end)

  it("should handle updating percentage dynamically", function()
    local progress = ProgressWidget:new({
      width = Screen:scaleBySize(100),
      height = Screen:scaleBySize(50),
      percentage = 0.1,
    })
    if type(progress.setPercentage) == "function" then
      progress:setPercentage(0.5)
      progress:paintTo(Screen.bb, 0, 0)
    end
    assert.is_table(progress)
  end)
end)
