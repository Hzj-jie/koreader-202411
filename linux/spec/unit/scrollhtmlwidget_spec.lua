describe("ScrollHtmlWidget module", function()
  local ScrollHtmlWidget, Screen, UIManager
  setup(function()
    require("commonrequire")
    Screen = require("device").screen
    ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
    UIManager = require("ui/uimanager")
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

  describe("Scrolling and Gestures", function()
    local widget
    local orig_setDirty

    before_each(function()
      orig_setDirty = UIManager.setDirty
      UIManager.setDirty = function() end

      widget = ScrollHtmlWidget:new({
        html_body = "<p>Line 1</p><p>Line 2</p><p>Line 3</p><p>Line 4</p><p>Line 5</p>",
        width = 300,
        height = 100,
      })
      widget.dialog = {
        movable = {
          alpha = 0.5,
          dimen = require("ui/geometry"):new({ w = 300, h = 100 }),
        },
      }
      -- Force page_count > 1 for testing
      widget.htmlbox_widget.page_count = 5
      widget.htmlbox_widget.page_number = 1
      widget.v_scroll_bar.enable = true
    end)

    after_each(function()
      UIManager.setDirty = orig_setDirty
    end)

    it("gets single page height and resets scroll", function()
      widget.htmlbox_widget.page_count = 1
      assert.is_number(widget:getSinglePageHeight())

      widget.htmlbox_widget.page_count = 5
      widget.htmlbox_widget.page_number = 3
      widget:resetScroll()
      assert.is_equal(1, widget.htmlbox_widget.page_number)
    end)

    it("scrolls to a specified ratio", function()
      widget:scrollToRatio(0.5)
      assert.is_equal(3, widget.htmlbox_widget.page_number)
      assert.is_nil(widget.dialog.movable.alpha)

      -- Clamping ratio
      widget:scrollToRatio(1.5)
      assert.is_equal(5, widget.htmlbox_widget.page_number)

      widget:scrollToRatio(-0.5)
      assert.is_equal(1, widget.htmlbox_widget.page_number)
    end)

    it("scrolls down and up via onScrollDown, onScrollUp, and scrollText", function()
      -- Scroll down
      assert.is_true(widget:onScrollDown())
      assert.is_equal(2, widget.htmlbox_widget.page_number)

      -- Scroll up
      assert.is_true(widget:onScrollUp())
      assert.is_equal(1, widget.htmlbox_widget.page_number)

      -- Already at top, scrolling up returns nil / false
      assert.is_nil(widget:onScrollUp())

      -- scrollText with 0 is a no-op
      widget:scrollText(0)
      assert.is_equal(1, widget.htmlbox_widget.page_number)
    end)

    it("handles onScrollText swipe gestures", function()
      assert.is_true(widget:onScrollText(nil, { direction = "north" }))
      assert.is_equal(2, widget.htmlbox_widget.page_number)

      assert.is_true(widget:onScrollText(nil, { direction = "south" }))
      assert.is_equal(1, widget.htmlbox_widget.page_number)

      assert.is_nil(widget:onScrollText(nil, { direction = "east" }))
    end)

    it("handles onTapScrollText tap gestures", function()
      local Geom = require("ui/geometry")
      -- Tap forward zone
      local ges_fwd = { pos = Geom:new({ x = 250, y = 50 }) }
      widget:onTapScrollText(nil, ges_fwd)
      assert.is_equal(2, widget.htmlbox_widget.page_number)

      -- Tap backward zone
      local ges_back = { pos = Geom:new({ x = 10, y = 50 }) }
      widget:onTapScrollText(nil, ges_back)
      assert.is_equal(1, widget.htmlbox_widget.page_number)
    end)
  end)
end)
