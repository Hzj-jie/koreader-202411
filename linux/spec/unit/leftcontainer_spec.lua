describe("LeftContainer widget", function()
  local LeftContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    LeftContainer = require("ui/widget/container/leftcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize left container", function()
    local inner_widget = Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = LeftContainer:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
