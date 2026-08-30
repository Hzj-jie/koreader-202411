describe("TopContainer widget", function()
  local TopContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    TopContainer = require("ui/widget/container/topcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize top container", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = TopContainer:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
