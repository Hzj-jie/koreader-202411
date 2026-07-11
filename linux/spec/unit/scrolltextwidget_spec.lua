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
    local expected_tss_160 =
      Screen:scaleBySize(ScrollTextWidget.DEFAULT_TEXT_SCROLL_SPAN)
    local widget_160 = ScrollTextWidget:new({ text = "test" })

    -- Calculate expected values dynamically at 320 DPI
    Screen:setDPI(320)
    local expected_sbw_320 =
      Screen:scaleBySize(ScrollTextWidget.DEFAULT_SCROLL_BAR_WIDTH)
    local expected_tss_320 =
      Screen:scaleBySize(ScrollTextWidget.DEFAULT_TEXT_SCROLL_SPAN)
    local widget_320 = ScrollTextWidget:new({ text = "test" })

    -- Verify that the test environment actually scales differently at 320 DPI
    assert.is_true(expected_sbw_160 < expected_sbw_320)
    assert.is_true(expected_tss_160 < expected_tss_320)

    -- Verify that dimensions in the instantiated widgets match the expected scaling
    assert.are.equal(expected_sbw_160, widget_160.scroll_bar_width)
    assert.are.equal(expected_sbw_320, widget_320.scroll_bar_width)
    assert.are.equal(expected_tss_160, widget_160.text_scroll_span)
    assert.are.equal(expected_tss_320, widget_320.text_scroll_span)
  end)
end)
