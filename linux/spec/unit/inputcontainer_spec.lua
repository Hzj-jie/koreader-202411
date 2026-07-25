describe("InputContainer widget", function()
  local InputContainer, Geom, Widget

  setup(function()
    require("commonrequire")
    InputContainer = require("ui/widget/container/inputcontainer")
    Geom = require("ui/geometry")
    Widget = require("ui/widget/widget")
  end)

  it("should initialize input container widget", function()
    local inner_widget = Widget:new({ dimen = Geom:new({ x = 0, y = 0, w = 50, h = 50 }) })
    local container = InputContainer:new({
      [1] = inner_widget,
    })

    assert.is_table(container)
  end)
end)
