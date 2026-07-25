describe("WidgetContainer widget", function()
  local WidgetContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    WidgetContainer = require("ui/widget/container/widgetcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize widget container", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = WidgetContainer:new({
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
