describe("TitleBar", function()
  local TitleBar
  local UIManager

  local orig_setDirty

  setup(function()
    require("commonrequire")
    TitleBar = require("ui/widget/titlebar")
    UIManager = require("ui/uimanager")

    orig_setDirty = UIManager.setDirty
  end)

  before_each(function()
    UIManager.setDirty = function() end
  end)

  after_each(function()
    UIManager.setDirty = orig_setDirty
  end)

  describe("initialization and alignments", function()
    it("should instantiate with default center alignment", function()
      local tb = TitleBar:new({
        title = "Main Title",
      })

      assert.are.equal("Main Title", tb.title)
      assert.are.equal("center", tb.align)
      assert.truthy(tb:getHeight())
      assert.truthy(tb.title_widget)
    end)

    it("should instantiate with left alignment and subtitle", function()
      local tb = TitleBar:new({
        title = "Left Title",
        align = "left",
        subtitle = "Detailed subtitle",
      })

      assert.are.equal("left", tb.align)
      assert.truthy(tb.inner_title_group)
      assert.truthy(tb.inner_subtitle_group)
      assert.truthy(tb.subtitle_widget)
    end)

    it("should handle close_callback and close_hold_callback", function()
      local close_tapped = false
      local close_held = false

      local tb = TitleBar:new({
        title = "Closable Bar",
        close_callback = function()
          close_tapped = true
        end,
        close_hold_callback = function()
          close_held = true
        end,
      })

      assert.is_true(tb.has_right_icon)
      assert.are.equal("close", tb.right_icon)
      assert.truthy(tb.right_button)

      tb.right_button.callback()
      assert.is_true(close_tapped)

      tb.right_button.hold_callback()
      assert.is_true(close_held)
    end)

    it("should handle left_icon and right_icon with callbacks", function()
      local left_tapped = false
      local right_tapped = false

      local tb = TitleBar:new({
        title = "Two Icons",
        left_icon = "appbar.menu",
        left_icon_tap_callback = function()
          left_tapped = true
        end,
        right_icon = "search",
        right_icon_tap_callback = function()
          right_tapped = true
        end,
      })

      assert.is_true(tb.has_left_icon)
      assert.is_true(tb.has_right_icon)
      assert.truthy(tb.left_button)
      assert.truthy(tb.right_button)

      tb.left_button.callback()
      assert.is_true(left_tapped)

      tb.right_button.callback()
      assert.is_true(right_tapped)

      local layout = tb:generateVerticalLayout()
      assert.are.equal(2, #layout)
    end)
  end)

  describe("multilines, shrink font, bottom line, and info text", function()
    it("should handle title_multilines and subtitle_multilines", function()
      local tb = TitleBar:new({
        title = "Very long title that wraps across multiple lines",
        title_multilines = true,
        subtitle = "Very long subtitle that also wraps across lines",
        subtitle_multilines = true,
      })

      assert.is_true(tb.title_multilines)
      assert.is_true(tb.subtitle_multilines)
    end)

    it("should handle title_shrink_font_to_fit", function()
      local tb = TitleBar:new({
        title = "Extremely long long long title text that must shrink to fit in single line",
        title_shrink_font_to_fit = true,
        width = 200,
      })

      assert.is_true(tb.title_shrink_font_to_fit)
      assert.truthy(tb:getHeight())
    end)

    it("should handle with_bottom_line and bottom_line_h_padding", function()
      local tb = TitleBar:new({
        title = "Bordered TitleBar",
        with_bottom_line = true,
        bottom_line_h_padding = 10,
      })

      assert.is_true(tb.with_bottom_line)
      assert.truthy(tb:getHeight())
    end)

    it("should handle info_text", function()
      local tb = TitleBar:new({
        title = "Info TitleBar",
        info_text = "Additional informative footnote",
      })

      assert.are.equal("Additional informative footnote", tb.info_text)
    end)

    it("should support subtitle_fullwidth and subtitle_truncate_left", function()
      local tb = TitleBar:new({
        title = "File path bar",
        subtitle = "/very/long/path/to/a/document/file.epub",
        subtitle_truncate_left = true,
        subtitle_fullwidth = true,
        align = "left",
      })

      assert.is_true(tb.subtitle_truncate_left)
      assert.is_true(tb.subtitle_fullwidth)
    end)
  end)

  describe("dynamic updates", function()
    it("should update title with setTitle for single line and multilines", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      -- Single line TextWidget
      local tb_single = TitleBar:new({
        title = "Initial",
        align = "left",
      })
      tb_single:setTitle("Updated Single")
      assert.is_true(dirty_called)

      -- Multiline TextBoxWidget
      dirty_called = false
      local tb_multi = TitleBar:new({
        title = "Initial Multi",
        title_multilines = true,
      })
      tb_multi:setTitle("Updated Multi Title")
      assert.is_true(dirty_called)
    end)

    it("should update subtitle with setSubTitle", function()
      local dirty_called = false
      UIManager.setDirty = function()
        dirty_called = true
      end

      local tb = TitleBar:new({
        title = "Title",
        subtitle = "Initial Subtitle",
        align = "left",
      })
      tb:setSubTitle("Updated Subtitle")
      assert.is_true(dirty_called)
    end)

    it("should update left and right icons with setLeftIcon and setRightIcon", function()
      local dirty_count = 0
      UIManager.setDirty = function()
        dirty_count = dirty_count + 1
      end

      local tb = TitleBar:new({
        title = "Icons Bar",
        left_icon = "appbar.menu",
        right_icon = "search",
      })

      tb:setLeftIcon("star")
      assert.are.equal("star", tb.left_button.icon)

      tb:setRightIcon("bookmark")
      assert.are.equal("bookmark", tb.right_button.icon)

      assert.are.equal(2, dirty_count)
    end)
  end)
end)
