describe("ScrollTextWidget module", function()
  local ScrollTextWidget, Screen
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    ScrollTextWidget = require("ui/widget/scrolltextwidget")
  end)

  teardown(function()
    -- Reset DPI to default to avoid affecting other tests
    if Screen then
      Screen:setDPI(nil)
    end
  end)

  it("should scale dimensions dynamically based on current DPI", function()
    -- Calculate expected values dynamically at 160 DPI
    Screen:setDPI(160)
    local expected_sbw_160 =
      Screen:scaleBySize(ScrollTextWidget.DEFAULT_SCROLL_BAR_WIDTH)
    local expected_rw_160 = 3 * expected_sbw_160 + Screen:scaleBySize(5)
    local widget_160 = ScrollTextWidget:new({ text = "test" })

    -- Calculate expected values dynamically at 320 DPI
    Screen:setDPI(320)
    local expected_sbw_320 =
      Screen:scaleBySize(ScrollTextWidget.DEFAULT_SCROLL_BAR_WIDTH)
    local expected_rw_320 = 3 * expected_sbw_320 + Screen:scaleBySize(5)
    local widget_320 = ScrollTextWidget:new({ text = "test" })

    -- Verify that the test environment actually scales differently at 320 DPI
    assert.is_true(expected_sbw_160 < expected_sbw_320)
    assert.is_true(expected_rw_160 < expected_rw_320)

    -- Verify that dimensions in the instantiated widgets match the expected scaling
    assert.are.equal(expected_sbw_160, widget_160.scroll_bar_width)
    assert.are.equal(expected_sbw_320, widget_320.scroll_bar_width)
    assert.are.equal(expected_rw_160, widget_160.reserved_width)
    assert.are.equal(expected_rw_320, widget_320.reserved_width)
  end)

  it("should respect text_scroll_span when explicitly passed", function()
    Screen:setDPI(160)
    local custom_span = 50
    local widget =
      ScrollTextWidget:new({ text = "test", text_scroll_span = custom_span })
    assert.are.equal(
      custom_span,
      widget.reserved_width - widget.v_scroll_bar:getRequiredWidth()
    )
  end)

  it("should enable scrollbar when text exceeds height", function()
    local text = "1\n2\n3\n4\n5\n6\n7\n8\n9\n10"
    local widget = ScrollTextWidget:new({
      text = text,
      height = 50,
      width = 200,
    })
    assert.is_true(widget.v_scroll_bar.enable)
  end)

  it("should disable scrollbar when text fits height", function()
    local text = "1\n2"
    local widget = ScrollTextWidget:new({
      text = text,
      height = 100,
      width = 200,
    })
    assert.is_false(widget.v_scroll_bar.enable)
  end)
end)
