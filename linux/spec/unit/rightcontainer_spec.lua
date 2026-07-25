describe("RightContainer widget", function()
  local RightContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    RightContainer = require("ui/widget/container/rightcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize right container", function()
    local inner_widget = Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = RightContainer:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
