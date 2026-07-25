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
