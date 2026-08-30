describe("ScrollHtmlWidget module", function()
  local ScrollHtmlWidget, Screen
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
  end)

  teardown(function()
    if Screen then
      Screen:setDPI(nil)
    end
  end)

  it("should scale at 160 DPI", function()
    Screen:setDPI(160)
    local expected_sbw_160 =
      Screen:scaleBySize(ScrollHtmlWidget.DEFAULT_SCROLL_BAR_WIDTH)
    local expected_rw_160 = 3 * expected_sbw_160 + Screen:scaleBySize(5)
    local widget_160 = ScrollHtmlWidget:new({
      html_body = "test",
      width = 200,
      height = 200,
    })
    assert.are.equal(expected_sbw_160, widget_160.scroll_bar_width)
    assert.are.equal(expected_rw_160, widget_160.reserved_width)
  end)

  it("should scale at 320 DPI", function()
    Screen:setDPI(320)
    local expected_sbw_320 =
      Screen:scaleBySize(ScrollHtmlWidget.DEFAULT_SCROLL_BAR_WIDTH)
    local expected_rw_320 = 3 * expected_sbw_320 + Screen:scaleBySize(5)
    local widget_320 = ScrollHtmlWidget:new({
      html_body = "test",
      width = 200,
      height = 200,
    })
    assert.are.equal(expected_sbw_320, widget_320.scroll_bar_width)
    assert.are.equal(expected_rw_320, widget_320.reserved_width)
  end)

  it("should respect text_scroll_span when explicitly passed", function()
    Screen:setDPI(160)
    local custom_span = 50
    local widget = ScrollHtmlWidget:new({
      html_body = "test",
      width = 200,
      height = 200,
      text_scroll_span = custom_span,
    })
    assert.are.equal(
      custom_span,
      widget.reserved_width - widget.scroll_bar_width
    )
  end)
end)
