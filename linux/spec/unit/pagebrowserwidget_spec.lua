describe("PageBrowserWidget widget", function()
  local PageBrowserWidget
  local Blitbuffer
  local Geom
  local UIManager
  local Widget
  local mock_ui

  local function make_mock_window(w)
    w._window = { x = 0, y = 0, widget = w }
    w.window = function(self)
      return self._window
    end
    UIManager:show(w)
    return w
  end

  setup(function()
    require("commonrequire")
    PageBrowserWidget = require("ui/widget/pagebrowserwidget")
    Blitbuffer = require("ffi/blitbuffer")
    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
    Widget = require("ui/widget/widget")
  end)

  before_each(function()
    G_reader_settings:save("items_per_page", 10)
    G_reader_settings:save("toc_items_per_page", 10)

    local dialog_widget = Widget:new({ dimen = Geom:new({ w = 600, h = 800 }) })
    make_mock_window(dialog_widget)

    mock_ui = {
      view = {
        shouldInvertBiDiLayoutMirroring = function()
          return false
        end,
      },
      document = {
        getPageCount = function()
          return 100
        end,
        hasHiddenFlows = function()
          return false
        end,
        getPageMap = function()
          return nil
        end,
        flows = {},
        getPageFlow = function(self, _p)
          return 0
        end,
        getPageNumberInFlow = function(self, p)
          return p
        end,
      },
      toc = {
        pageno = 10,
        toc_depth = 3,
        toc_items_per_page_default = 10,
        fillToc = function() end,
        toc = {
          { page = 1, depth = 1, title = "Chapter 1", seq_in_level = 1 },
          { page = 20, depth = 1, title = "Chapter 2", seq_in_level = 2 },
          { page = 30, depth = 2, title = "Section 2.1", seq_in_level = 1 },
        },
      },
      doc_settings = {
        read = function(self, _key)
          return nil
        end,
        isTrue = function(self, _key)
          return false
        end,
        nilOrFalse = function(self, _key)
          return true
        end,
        save = function(self, _key, _val, _default) end,
      },
      bookmark = {
        getBookmarkedPages = function()
          return {}
        end,
        onPageUpdate = function() end,
        toggleBookmark = function() end,
      },
      link = {
        getPreviousLocationPages = function()
          return {}
        end,
        addCurrentLocationToStack = function() end,
      },
      handmade = {
        custom_toc_symbol = "✎",
        isHandmadeTocEnabled = function()
          return false
        end,
        isHandmadeTocEditEnabled = function()
          return false
        end,
        isHandmadeHiddenFlowsEnabled = function()
          return false
        end,
        isHandmadeHiddenFlowsEditEnabled = function()
          return false
        end,
        hasPageTocItem = function()
          return false
        end,
        addOrEditPageTocItem = function() end,
        isInHiddenFlow = function()
          return false
        end,
        toggleHiddenFlow = function() end,
      },
      thumbnail = {
        cancelPageThumbnailRequests = function() end,
        getPageThumbnail = function(self, _page, w, h, batch_id, callback)
          if callback then
            local buf = Blitbuffer.new(w or 100, h or 100)
            callback({ bb = buf }, batch_id, false)
          end
          return false
        end,
        tidyCache = function() end,
      },
      dialog = dialog_widget,
      getCurrentPage = function()
        return 10
      end,
    }
  end)

  it("should initialize PageBrowserWidget correctly", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    assert.is_table(widget)
    assert.are.equal(100, widget.nb_pages)
    assert.are.equal(10, widget.cur_page)
    assert.are.equal(3, widget.nb_cols)
    assert.are.equal(2, widget.nb_rows)
    assert.are.equal(6, widget.nb_grid_items)
  end)

  it("should update layout and settings", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })

    -- Test nb_cols update
    assert.is_true(widget:updateNbCols(1, true))
    assert.are.equal(4, widget.nb_cols)
    assert.is_false(widget:updateNbCols(4, false)) -- same value returns false

    -- Test nb_rows update
    assert.is_true(widget:updateNbRows(1, true))
    assert.are.equal(3, widget.nb_rows)
    assert.is_false(widget:updateNbRows(3, false))

    -- Test bounds clamping for cols
    widget:updateNbCols(10, false)
    assert.are.equal(widget.max_nb_cols, widget.nb_cols)
    widget:updateNbCols(0, false)
    assert.are.equal(widget.min_nb_cols, widget.nb_cols)

    -- Test bounds clamping for rows
    widget:updateNbRows(10, false)
    assert.are.equal(widget.max_nb_rows, widget.nb_rows)
    widget:updateNbRows(0, false)
    assert.are.equal(widget.min_nb_rows, widget.nb_rows)
  end)

  it("should update nb_toc_spans correctly", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })

    assert.is_true(widget:updateNbTocSpans(-1, true))
    assert.are.equal(2, widget.nb_toc_spans)

    -- Rollover test
    widget.nb_toc_spans = 0
    assert.is_true(widget:updateNbTocSpans(-1, true, true))
    assert.are.equal(widget.max_toc_depth, widget.nb_toc_spans)

    assert.is_true(widget:updateNbTocSpans(1, true, true))
    assert.are.equal(0, widget.nb_toc_spans)
  end)

  it("should update thumbnail page numbers display type", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })

    assert.is_true(widget:updateThumbnailPageNumsDisplayType(-1, true))
    assert.are.equal(1, widget.thumbnails_pagenums)

    assert.is_true(widget:updateThumbnailPageNumsDisplayType(-1, true))
    assert.are.equal(0, widget.thumbnails_pagenums)

    -- Clamping
    assert.is_false(widget:updateThumbnailPageNumsDisplayType(-1, true))
    assert.are.equal(0, widget.thumbnails_pagenums)

    assert.is_true(widget:updateThumbnailPageNumsDisplayType(5, false))
    assert.are.equal(2, widget.thumbnails_pagenums)
  end)

  it("should update focus page and scroll", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    local initial_focus = widget.focus_page

    assert.is_true(widget:onScrollRowDown())
    assert.are.equal(initial_focus + widget.nb_cols, widget.focus_page)

    assert.is_true(widget:onScrollRowUp())
    assert.are.equal(initial_focus, widget.focus_page)

    assert.is_true(widget:onScrollPageDown())
    assert.are.equal(initial_focus + widget.nb_grid_items, widget.focus_page)

    assert.is_true(widget:onScrollPageUp())
    assert.are.equal(initial_focus, widget.focus_page)
  end)

  it(
    "should handle gesture events: swipe, pinch, spread, pan, multiswipe",
    function()
      local Device = require("device")
      local widget = PageBrowserWidget:new({
        ui = mock_ui,
      })
      make_mock_window(widget)

      -- Pan / mousewheel
      assert.is_true(
        widget:onPan(nil, { mousewheel_direction = true, direction = "north" })
      )
      assert.is_true(
        widget:onPan(nil, { mousewheel_direction = true, direction = "south" })
      )

      -- Pinch
      assert.is_true(widget:onPinch(nil, { direction = "horizontal" }))
      assert.is_true(widget:onPinch(nil, { direction = "vertical" }))
      assert.is_true(widget:onPinch(nil, { direction = "diagonal" }))

      -- Spread
      assert.is_true(widget:onSpread(nil, { direction = "horizontal" }))
      assert.is_true(widget:onSpread(nil, { direction = "vertical" }))
      assert.is_true(widget:onSpread(nil, { direction = "diagonal" }))

      -- Swipe north / south
      local screen_w = Device.screen:getWidth()
      local screen_h = Device.screen:getHeight()

      -- Left edge swipe for rows
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "north",
            pos = Geom:new({ x = screen_w * 0.05, y = screen_h * 0.5 }),
          }
        )
      )
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "south",
            pos = Geom:new({ x = screen_w * 0.05, y = screen_h * 0.5 }),
          }
        )
      )

      -- Main area vertical swipe
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "north",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
          }
        )
      )
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "south",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
          }
        )
      )

      -- Top edge swipe for cols
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "west",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.05 }),
          }
        )
      )
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "east",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.05 }),
          }
        )
      )

      -- Bottom ribbon swipe
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "west",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h - 10 }),
          }
        )
      )

      -- Main area horizontal swipe
      assert.is_true(
        widget:onSwipe(
          nil,
          {
            direction = "west",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
          }
        )
      )

      -- Diagonal swipe
      assert.is_false(
        widget:onSwipe(
          nil,
          {
            direction = "northeast",
            pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
          }
        )
      )

      -- MultiSwipe
      assert.is_true(widget:onMultiSwipe())
    end
  )

  it("should handle tap events", function()
    local Device = require("device")
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    make_mock_window(widget)

    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()

    -- Tap title bar
    assert.is_true(
      widget:onTap(nil, { pos = Geom:new({ x = screen_w * 0.5, y = 5 }) })
    )

    -- Tap bottom ribbon
    assert.is_true(
      widget:onTap(
        nil,
        { pos = Geom:new({ x = screen_w * 0.5, y = screen_h - 5 }) }
      )
    )

    -- Tap blank area for forward / backward navigation
    assert.is_true(
      widget:onTap(
        nil,
        { pos = Geom:new({ x = screen_w * 0.9, y = screen_h * 0.5 }) }
      )
    )
    assert.is_true(
      widget:onTap(
        nil,
        { pos = Geom:new({ x = screen_w * 0.1, y = screen_h * 0.5 }) }
      )
    )
  end)

  it("should handle hold events and thumbnail hold dialogs", function()
    local Device = require("device")
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    make_mock_window(widget)

    local screen_w = Device.screen:getWidth()
    local screen_h = Device.screen:getHeight()

    -- Hold on title bar
    assert.is_true(
      widget:onHold(nil, { pos = Geom:new({ x = screen_w * 0.5, y = 5 }) })
    )

    -- Hold on bottom ribbon
    assert.is_true(
      widget:onHold(
        nil,
        { pos = Geom:new({ x = screen_w * 0.5, y = screen_h - 5 }) }
      )
    )
    if #UIManager._window_stack > 1 then
      UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end

    -- Hold on thumbnail with handmade edit options disabled
    local bookmark_toggled = false
    mock_ui.bookmark.toggleBookmark = function(self, _page)
      bookmark_toggled = true
    end
    widget:onThumbnailHold(1, { pos = Geom:new({ x = 100, y = 100 }) })
    assert.is_true(bookmark_toggled)

    -- Hold on thumbnail with handmade edit options enabled
    mock_ui.handmade.isHandmadeTocEnabled = function()
      return true
    end
    mock_ui.handmade.isHandmadeTocEditEnabled = function()
      return true
    end
    mock_ui.handmade.isHandmadeHiddenFlowsEnabled = function()
      return true
    end
    mock_ui.handmade.isHandmadeHiddenFlowsEditEnabled = function()
      return true
    end
    widget:onThumbnailHold(1, { pos = Geom:new({ x = 100, y = 100 }) })
    if #UIManager._window_stack > 1 then
      UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end
  end)

  it("should test dialog views and menu options", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    make_mock_window(widget)

    widget:showAbout()
    if #UIManager._window_stack > 1 then
      UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end

    widget:showGestures()
    if #UIManager._window_stack > 1 then
      UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end

    widget:showMenu()
    if #UIManager._window_stack > 1 then
      UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
    end
  end)

  it("should test preloadNextPrevScreenThumbnails and saveSettings", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })

    widget:preloadThumbnail(1, "test")
    widget:preloadNextPrevScreenThumbnails()
    widget:saveSettings(true)
  end)

  it("should handle editable stuff updates and exit", function()
    local widget = PageBrowserWidget:new({
      ui = mock_ui,
    })
    make_mock_window(widget)

    widget:updateEditableStuff(true)
    assert.is_true(widget.editable_stuff_edited)

    -- Test exit without launcher
    assert.is_true(widget:onExit(false))

    -- Test exit with launcher
    local mock_launcher = Widget:new({
      dimen = Geom:new({ w = 600, h = 800 }),
      onExit = function() end,
      updateEditableStuff = function() end,
    })
    make_mock_window(mock_launcher)

    local widget_with_launcher = PageBrowserWidget:new({
      ui = mock_ui,
      launcher = mock_launcher,
    })
    make_mock_window(widget_with_launcher)
    assert.is_true(widget_with_launcher:onExit(false))
  end)

  it(
    "should support hidden flows and page labels in pagebrowser update",
    function()
      -- Enable hidden flows
      mock_ui.document.hasHiddenFlows = function()
        return true
      end
      mock_ui.document.flows = { { 1, 5 } }
      mock_ui.document.getPageFlow = function(self, p)
        return p <= 5 and 1 or 0
      end
      mock_ui.document.getPageNumberInFlow = function(self, p)
        return p
      end

      -- Enable page labels
      mock_ui.pagemap = {
        wantsPageLabels = function()
          return true
        end,
        cleanPageLabel = function(self, label)
          return label
        end,
      }
      mock_ui.document.getPageMap = function()
        return {
          { page = 1, label = "i" },
          { page = 5, label = "1" },
        }
      end

      local widget = PageBrowserWidget:new({
        ui = mock_ui,
      })
      assert.is_table(widget)
      assert.is_table(widget.hidden_flows)
      assert.is_table(widget.page_labels)
    end
  )
end)
