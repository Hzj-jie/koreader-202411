describe("FootnoteWidget module", function()
  local FootnoteWidget

  setup(function()
    require("commonrequire")
    FootnoteWidget = require("ui/widget/footnotewidget")
  end)

  it("should initialize with positive dimensions", function()
    local footnote = FootnoteWidget:new({
      html = "<html><body><p>Test footnote content</p></body></html>",
    })
    assert.is_not_nil(footnote)
    local size = footnote:getSize()
    assert.is_not_nil(size)
    assert.is_true(size.w > 0)
    assert.is_true(size.h > 0)
  end)

  it("should trigger follow and close callbacks on onFollow and onExit", function()
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

    footnote:onFollow()
    assert.is_true(follow_called)
    assert.is_true(close_called)

    close_called = false
    footnote:onExit()
    assert.is_true(close_called)
  end)
end)

describe("FootnoteWidget", function()
  local FootnoteWidget, Geom, UIManager, BD, Device

  setup(function()
    require("commonrequire")
    FootnoteWidget = require("ui/widget/footnotewidget")
    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
    BD = require("ui/bidi")
    Device = require("device")
  end)

  it("should initialize footnote widget with HTML content and custom font settings", function()
    G_reader_settings:save("footnote_popup_absolute_font_size", 18)
    local widget = FootnoteWidget:new({
      html = "<div>abc<br anyattr='val'/>def<span id='foot1'>note</span></div>",
      doc_margins = { left = 20, right = 20 },
    })

    assert.is_table(widget)
    assert.truthy(widget.html)
    assert.is_not_nil(widget.width)
    assert.is_not_nil(widget.height)
    G_reader_settings:save("footnote_popup_absolute_font_size", nil)
  end)

  it("should handle onShow and onClose dirty regions", function()
    local widget = FootnoteWidget:new({
      html = "<p>Sample</p>",
    })

    local dirty_widget, dirty_func
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, w, f)
      dirty_widget = w
      dirty_func = f
    end

    widget:onShow()
    assert.truthy(dirty_func)
    local mode, region = dirty_func()
    assert.are.equal("ui", mode)

    widget:onClose()
    assert.truthy(dirty_func)
    local mode_c, region_c = dirty_func()
    assert.are.equal("partial", mode_c)

    UIManager.setDirty = orig_setDirty
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

  it("should handle tap close gesture event when tapped outside container", function()
    local tap_closed = false
    local widget = FootnoteWidget:new({
      html = "<p>Footnote text</p>",
      on_tap_close_callback = function()
        tap_closed = true
      end,
    })

    widget.container = { dimen = Geom:new({ x = 10, y = 10, w = 100, h = 100 }) }
    local res = widget:onTapClose(nil, { pos = Geom:new({ x = 500, y = 500 }) })
    assert.is_true(res)
    assert.is_true(tap_closed)

    -- Inside container tap returns false
    local res_inside = widget:onTapClose(nil, { pos = Geom:new({ x = 50, y = 50 }) })
    assert.is_false(res_inside)
  end)

  it("should handle onSwipeFollow across all directions", function()
    local followed = false
    local closed = false
    local refreshed = nil

    local orig_refresh = UIManager.scheduleRefresh
    UIManager.scheduleRefresh = function(self, mode)
      refreshed = mode
    end

    local widget = FootnoteWidget:new({
      html = "<p>Swipe text</p>",
      follow_callback = function()
        followed = true
        return true
      end,
      close_callback = function()
        closed = true
      end,
    })

    -- West -> Follow
    assert.is_true(widget:onSwipeFollow(nil, { direction = "west" }))
    assert.is_true(followed)
    assert.is_true(closed)

    -- South -> Close
    closed = false
    assert.is_true(widget:onSwipeFollow(nil, { direction = "south" }))
    assert.is_true(closed)

    -- East -> Close
    closed = false
    assert.is_true(widget:onSwipeFollow(nil, { direction = "east" }))
    assert.is_true(closed)

    -- North -> No-op
    assert.is_false(widget:onSwipeFollow(nil, { direction = "north" }))

    -- Diagonal -> Full refresh
    assert.is_false(widget:onSwipeFollow(nil, { direction = "northeast" }))
    assert.are.equal("full", refreshed)

    UIManager.scheduleRefresh = orig_refresh
  end)
end)
