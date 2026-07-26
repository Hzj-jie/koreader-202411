describe("FootnoteWidget module", function()
  local FootnoteWidget

  setup(function()
    require("commonrequire")
    FootnoteWidget = require("ui/widget/footnotewidget")
  end)

  it(
    "should initialize with correct sizes and handle callbacks on exit and follow",
    function()
      local close_called = false
      local follow_called = false

      local footnote = FootnoteWidget:new({
        html = "<html><body><p>Test footnote content</p></body></html>",
        close_callback = function(_h)
          close_called = true
        end,
        follow_callback = function()
          follow_called = true
        end,
      })

      assert.is_not_nil(footnote)
      local size = footnote:getSize()
      assert.is_not_nil(size)
      assert.is_true(size.w > 0)
      assert.is_true(size.h > 0)

      -- Test onFollow callback
      footnote:onFollow()
      assert.is_true(follow_called)
      assert.is_true(close_called)

      -- Test onExit callback
      close_called = false
      footnote:onExit()
      assert.is_true(close_called)
    end
  )
end)

describe("FootnoteWidget", function()
  local FootnoteWidget, Geom

  setup(function()
    require("commonrequire")
    FootnoteWidget = require("ui/widget/footnotewidget")
    Geom = require("ui/geometry")
  end)

  it("should initialize footnote widget with HTML content", function()
    local widget = FootnoteWidget:new({
      html = "<p>This is a sample footnote content.</p>",
    })

    assert.is_table(widget)
    assert.are.equal("<p>This is a sample footnote content.</p>", widget.html)
    assert.is_not_nil(widget.width)
    assert.is_not_nil(widget.height)
  end)

  it("should handle close and follow callbacks", function()
    local closed = false
    local followed = false

    local widget = FootnoteWidget:new({
      html = "<p>Footnote text</p>",
      close_callback = function()
        closed = true
      end,
      follow_callback = function()
        followed = true
        return true
      end,
    })

    widget:onExit()
    assert.is_true(closed)

    widget:onFollow()
    assert.is_true(followed)
  end)

  it(
    "should handle tap close gesture event when tapped outside container",
    function()
      local tap_closed = false
      local widget = FootnoteWidget:new({
        html = "<p>Footnote text</p>",
        on_tap_close_callback = function()
          tap_closed = true
        end,
      })

      widget.container =
        { dimen = Geom:new({ x = 10, y = 10, w = 100, h = 100 }) }
      local res =
        widget:onTapClose(nil, { pos = Geom:new({ x = 500, y = 500 }) })

      assert.is_true(res)
      assert.is_true(tap_closed)
    end
  )
end)
