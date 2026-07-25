describe("BBoxWidget widget", function()
  local BBoxWidget

  setup(function()
    require("commonrequire")
    BBoxWidget = require("ui/widget/bboxwidget")
  end)

  it("should initialize BBoxWidget class", function()
    assert.is_table(BBoxWidget)
    assert.is_function(BBoxWidget.new)
  end)
end)
