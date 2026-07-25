describe("AlphaContainer widget", function()
  local AlphaContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    AlphaContainer = require("ui/widget/container/alphacontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize alpha container", function()
    local inner_widget = Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = AlphaContainer:new({
      [1] = inner_widget,
      alpha = 0.5,
    })

    assert.is_table(container)
    assert.are.equal(0.5, container.alpha)
  end)
end)
