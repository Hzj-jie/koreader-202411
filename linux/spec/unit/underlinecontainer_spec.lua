describe("UnderlineContainer widget", function()
  local UnderlineContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    UnderlineContainer = require("ui/widget/container/underlinecontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize underline container", function()
    local inner_widget =
      Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = UnderlineContainer:new({
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
