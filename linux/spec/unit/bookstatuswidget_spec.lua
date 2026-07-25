describe("BookStatusWidget widget", function()
  local BookStatusWidget

  setup(function()
    require("commonrequire")
    BookStatusWidget = require("ui/widget/bookstatuswidget")
  end)

  it("should initialize BookStatusWidget class", function()
    assert.is_table(BookStatusWidget)
    assert.is_function(BookStatusWidget.new)
  end)
end)
