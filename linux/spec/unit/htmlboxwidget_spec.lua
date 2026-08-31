describe("HtmlBoxWidget module", function()
  local HtmlBoxWidget, Blitbuffer, Geom, Mupdf, Device

  setup(function()
    require("commonrequire")
    package.unloadAll()
    local device = require("device")
    require("document/canvascontext"):init(device)

    HtmlBoxWidget = require("ui/widget/htmlboxwidget")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
    Mupdf = require("ffi/mupdf")
    Device = require("device")
  end)

  it("should initialize touch gesture events", function()
    local orig_is_touch = Device.isTouchDevice
    Device.isTouchDevice = function() return true end

    local widget = HtmlBoxWidget:new({
      dimen = Geom:new({ x = 0, y = 0, w = 100, h = 100 }),
    })
    assert.is_not_nil(widget.ges_events.TapText)
    assert.are_equal(widget.dimen, widget.ges_events.TapText[1].range())

    Device.isTouchDevice = orig_is_touch
  end)

  it("should set content and handle fallback parsing when Mupdf errors", function()
    local mock_doc = {
      layoutDocument = function() end,
      getPages = function() return 1 end,
      close = function() end,
    }

    local widget = HtmlBoxWidget:new({
      width = 200,
      height = 100,
    })

    -- 1. Normal setContent
    local orig_open = Mupdf.openDocumentFromText
    Mupdf.openDocumentFromText = function(html, mimetype)
      return mock_doc
    end

    widget:setContent("<p>Hello</p><br/>", "p { font-size: 12px; }", 12, true, false)
    assert.are_equal(mock_doc, widget.document)
    assert.are_equal(1, widget.page_count)

    -- 2. First open fails, fallback succeeds
    local call_count = 0
    Mupdf.openDocumentFromText = function(html, mimetype)
      call_count = call_count + 1
      if call_count == 1 then
        error("first parse error")
      end
      return mock_doc
    end

    widget:setContent("<p>Malformed HTML\nwith line break</p>", nil, 12, false, true)
    assert.are_equal(2, call_count)
    assert.are_equal(mock_doc, widget.document)

    -- 3. Both open attempts fail -> raises error
    Mupdf.openDocumentFromText = function(html, mimetype)
      error("fatal parse error")
    end
    assert.has_error(function()
      widget:setContent("<p>Fatal</p>")
    end)

    Mupdf.openDocumentFromText = orig_open
  end)

  it("should render, paint to target blitbuffer with highlights, and calculate single page height", function()
    local page_closed = false
    local painted_rects = {}
    local mock_bb = {
      getHighlightColor = function(self, alpha) return 12345 end,
      paintRect = function(self, x, y, w, h, color, blend)
        table.insert(painted_rects, { x = x, y = y, w = w, h = h })
      end,
      free = function() end,
    }

    local mock_page = {
      draw_new = function(self, _dc, w, h, x, y)
        return mock_bb
      end,
      getUsedBBox = function()
        return 0, 0, 100, 150.4
      end,
      close = function()
        page_closed = true
      end,
    }

    local mock_document = {
      openPage = function(self, num)
        page_closed = false
        return mock_page
      end,
      setColorRendering = function() end,
      close = function() end,
    }

    local widget = HtmlBoxWidget:new({
      document = mock_document,
      page_count = 1,
      page_number = 1,
      width = 200,
      height = 100,
      highlight_rects = {
        { x0 = 10, y0 = 10, x1 = 50, y1 = 30 },
      },
    })

    -- getSinglePageHeight when page_count == 1
    local h = widget:getSinglePageHeight()
    assert.are_equal(151, h)

    -- getSinglePageHeight when page_count > 1
    widget.page_count = 2
    assert.is_nil(widget:getSinglePageHeight())
    widget.page_count = 1

    -- paintTo renders and highlights
    local target_bb = {
      blitFrom = function(self, src, dx, dy, sx, sy, w, h) end,
    }
    widget:paintTo(target_bb, 0, 0)
    assert.are_equal(mock_bb, widget.bb)
    assert.are_equal(1, #painted_rects)
    assert.are_equal(10, painted_rects[1].x)
    assert.are_equal(40, painted_rects[1].w)

    -- Second paintTo reuses widget.bb
    widget:paintTo(target_bb, 0, 0)

    -- Free and onClose
    widget:onClose()
    assert.is_nil(widget.bb)
    assert.is_nil(widget.document)
  end)

  it("should set and clear highlight rects on drag/pan and release", function()
    local mock_page = {
      getPageText = function()
        return {
          {
            "non-table item",
            { word = "Hello", x0 = 0, y0 = 0, x1 = 50, y1 = 20 },
            { word = "World", x0 = 60, y0 = 0, x1 = 110, y1 = 20 },
          },
          {
            { word = "Second", x0 = 0, y0 = 30, x1 = 60, y1 = 50 },
            { word = "Line", x0 = 70, y0 = 30, x1 = 120, y1 = 50 },
          },
        }
      end,
      draw_new = function(self, _dc, w, h)
        return Blitbuffer.new(w, h)
      end,
      close = function() end,
    }

    local mock_document = {
      layoutDocument = function() end,
      getPages = function() return 1 end,
      setColorRendering = function() end,
      openPage = function() return mock_page end,
      close = function() end,
    }

    local widget = HtmlBoxWidget:new({
      document = mock_document,
      dimen = Geom:new({ x = 0, y = 0, w = 200, h = 100 }),
    })

    -- 1. HoldStart with invalid / outside coordinate returns false
    assert.is_false(widget:onHoldStartText(nil, { pos = { x = 300, y = 300 } }))
    assert.is_nil(widget.hold_start_pos)

    -- 2. Valid HoldStart
    assert.is_true(widget:onHoldStartText(nil, { pos = { x = 10, y = 10 } }))
    assert.is_not_nil(widget.hold_start_pos)

    -- 3. HoldPan without hold_start_pos
    local saved_start = widget.hold_start_pos
    widget.hold_start_pos = nil
    assert.is_false(widget:onHoldPanText(nil, { pos = { x = 80, y = 10 } }))
    widget.hold_start_pos = saved_start

    -- 4. HoldPan with out-of-bounds pos returns true
    assert.is_true(widget:onHoldPanText(nil, { pos = { x = -50, y = 10 } }))

    -- 5. Pan to select across multiple words
    widget:onHoldPanText(nil, { pos = { x = 80, y = 10 } })
    assert.is_not_nil(widget.highlight_rects)
    assert.are.equal(2, #widget.highlight_rects)

    -- 6. Panning to exact same position triggers no change
    widget:onHoldPanText(nil, { pos = { x = 80, y = 10 } })

    -- 7. Reverse selection (end before start)
    local words, rects = widget:getSelectedWordsAndRects(mock_page:getPageText(), Geom:new({ x = 80, y = 10 }), Geom:new({ x = 10, y = 10 }))
    assert.are_equal(2, #words)

    -- 8. Multi-line selection and early break
    local multi_words = widget:getSelectedWordsAndRects(mock_page:getPageText(), Geom:new({ x = 10, y = 10 }), Geom:new({ x = 30, y = 40 }))
    assert.are_equal(3, #multi_words)

    -- 9. HoldRelease edge cases
    assert.is_false(widget:onHoldReleaseText(nil, { pos = { x = 80, y = 10 } }))
    assert.is_false(widget:onHoldReleaseText(function() end, { pos = { x = 500, y = 500 } }))

    -- 10. Valid HoldRelease
    local called = false
    widget.hold_start_pos = Geom:new({ x = 10, y = 10 })
    widget:onHoldReleaseText(function(text, _duration)
      assert.are.equal("Hello World", text)
      called = true
    end, { pos = { x = 80, y = 10 } })

    assert.is_true(called)
    assert.is_nil(widget.highlight_rects)
  end)

  it("should handle links and onTapText", function()
    local mock_page = {
      getPageLinks = function()
        return {
          { uri = "https://koreader.rocks", x0 = 10, y0 = 10, x1 = 80, y1 = 30 },
        }
      end,
      close = function() end,
    }

    local mock_document = {
      openPage = function() return mock_page end,
      close = function() end,
    }

    local tapped_link = nil
    local widget = HtmlBoxWidget:new({
      document = mock_document,
      dimen = Geom:new({ x = 0, y = 0, w = 200, h = 100 }),
      html_link_tapped_callback = function(link)
        tapped_link = link
      end,
    })

    -- Setting tap_to_follow_links = false returns early
    G_reader_settings:save("tap_to_follow_links", false)
    assert.is_nil(widget:onTapText(nil, { pos = { x = 20, y = 20 } }))
    G_reader_settings:save("tap_to_follow_links", nil)

    -- Tap outside widget area
    assert.is_nil(widget:onTapText(nil, { pos = { x = 300, y = 300 } }))

    -- Tap inside widget but outside any link
    assert.is_nil(widget:onTapText(nil, { pos = { x = 150, y = 50 } }))

    -- Tap on link
    assert.is_true(widget:onTapText(nil, { pos = { x = 25, y = 20 } }))
    assert.is_not_nil(tapped_link)
    assert.are_equal("https://koreader.rocks", tapped_link.uri)
  end)
end)
