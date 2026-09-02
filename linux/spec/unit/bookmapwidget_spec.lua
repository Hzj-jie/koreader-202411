describe("BookMapWidget callbacks", function()
  local BookMapWidget, UIManager
  local mock_ui

  setup(function()
    require("commonrequire")
    BookMapWidget = require("ui/widget/bookmapwidget")
    UIManager = require("ui/uimanager")

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
        getPageMap = function() end,
        hasHiddenFlows = function()
          return false
        end,
        flows = {},
      },
      toc = {
        pageno = 1,
        toc_depth = 1,
        fillToc = function() end,
        toc_items_per_page_default = 10,
        toc = {},
      },
      bookmark = {
        getBookmarkedPages = function()
          return {}
        end,
      },
      doc_settings = {
        isTrue = function()
          return false
        end,
        read = function()
          return nil
        end,
      },
      handmade = {
        isHandmadeTocEnabled = function()
          return false
        end,
      },
      link = {
        getPreviousLocationPages = function()
          return {}
        end,
        addCurrentLocationToStack = function() end,
      },
    }
  end)

  it("should trigger on_exit callback when onExit is called", function()
    local exit_called = false
    local bm = BookMapWidget:new({
      ui = mock_ui,
      on_exit = function(_close_all)
        exit_called = true
      end,
    })

    -- Stub UIManager.close since we don't need to close windows
    local original_close = UIManager.close
    UIManager.close = function() end

    bm:onExit(true)
    assert.is_true(exit_called)

    UIManager.close = original_close
  end)

  it(
    "should trigger on_update callback when exiting after editable stuff was edited",
    function()
      local update_called = false
      local bm = BookMapWidget:new({
        ui = mock_ui,
        on_update = function()
          update_called = true
        end,
      })

      -- Stub UIManager.close since we don't need to close windows
      local original_close = UIManager.close
      UIManager.close = function() end

      bm:updateEditableStuff(true)
      bm:onExit(false)
      assert.is_true(update_called)

      UIManager.close = original_close
    end
  )

  it("should calculate dimensions via getSize", function()
    local bm = BookMapWidget:new({
      ui = mock_ui,
    })
    local size = bm:getSize()
    assert.is_not_nil(size)
  end)

  it("should expose BookMapRow subwidget", function()
    assert.is_table(BookMapWidget.BookMapRow)
  end)
end)

describe("BookMapWidget ReaderUI Integration", function()
  local DocumentRegistry, ReaderUI, UIManager, Screen, DocSettings, BookMapWidget, PageBrowserWidget
  local sample_epub

  setup(function()
    require("commonrequire")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    BookMapWidget = require("ui/widget/bookmapwidget")
    PageBrowserWidget = require("ui/widget/pagebrowserwidget")

    sample_epub = "spec/front/unit/data/juliet.epub"
  end)

  it("should show BookMap from ReaderThumbnail with root exit handler", function()
    DocSettings:open(sample_epub):purge()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    readerui.status.enabled = false

    assert.truthy(UIManager:isWindowWidget(readerui))

    readerui.thumbnail:onShowBookMap()
    local bookmap
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if getmetatable(w) == BookMapWidget then
        bookmap = w
        break
      end
    end
    assert.truthy(bookmap)
    assert.falsy(bookmap.on_exit)
    assert.falsy(bookmap.on_update)
    assert.truthy(bookmap.on_root_exit)

    UIManager:close(bookmap)
    UIManager:close(readerui)
    UIManager:quit()
  end)

  it("should transition from BookMap to PageBrowser and return on exit", function()
    DocSettings:open(sample_epub):purge()
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    readerui.status.enabled = false

    readerui.thumbnail:onShowBookMap()
    local bookmap
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if getmetatable(w) == BookMapWidget then
        bookmap = w
        break
      end
    end
    assert.truthy(bookmap)

    bookmap.getVGroupRowAtY = function()
      return {
        start_page = 10,
        getPageAtX = function()
          return 10
        end,
      }
    end

    local original_settings_nilOrTrue = G_reader_settings.nilOrTrue
    G_reader_settings.nilOrTrue = function()
      return true
    end

    local Geom = require("ui/geometry")
    bookmap:onTap(nil, { pos = Geom:new({ x = 100, y = 100 }) })

    local pagebrowser
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if getmetatable(w) == PageBrowserWidget then
        pagebrowser = w
        break
      end
    end
    assert.truthy(pagebrowser)
    assert.truthy(pagebrowser.on_exit)
    assert.truthy(pagebrowser.on_update)

    pagebrowser:onExit(false)

    local found_bookmap = false
    for i = #UIManager._window_stack, 1, -1 do
      local w = UIManager._window_stack[i].widget
      if getmetatable(w) == BookMapWidget then
        found_bookmap = true
        break
      end
    end
    assert.is_true(found_bookmap)

    G_reader_settings.nilOrTrue = original_settings_nilOrTrue
    UIManager:close(bookmap)
    UIManager:close(readerui)
    UIManager:quit()
  end)
end)

describe("BookMapWidget widget", function()
  local BookMapWidget
  local BookMapRow
  local Blitbuffer
  local Event
  local Font
  local Geom
  local UIManager
  local Widget

  local mock_ui
  local dialog_widget

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
    BookMapWidget = require("ui/widget/bookmapwidget")
    BookMapRow = BookMapWidget.BookMapRow
    Blitbuffer = require("ffi/blitbuffer")
    Event = require("ui/event")
    Font = require("ui/font")
    Geom = require("ui/geometry")
    UIManager = require("ui/uimanager")
    Widget = require("ui/widget/widget")
  end)

  before_each(function()
    G_reader_settings:save("book_map_ten_pages_markers", 0)
    G_reader_settings:save("book_map_alt_theme", false)
    G_reader_settings:save("book_map_tap_to_page_browser", true)

    dialog_widget = Widget:new({ dimen = Geom:new({ w = 600, h = 800 }) })
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
        cleanUpTocTitle = function(self, title)
          return title
        end,
        toc = {
          { page = 1, depth = 1, title = "Chapter 1", seq_in_level = 1 },
          { page = 20, depth = 1, title = "Chapter 2", seq_in_level = 2 },
          { page = 30, depth = 2, title = "Section 2.1", seq_in_level = 1 },
        },
      },
      doc_settings = {
        _settings = {},
        read = function(self, key)
          return self._settings[key]
        end,
        isTrue = function(self, key)
          return self._settings[key] == true
        end,
        nilOrFalse = function(self, key)
          return not self._settings[key]
        end,
        save = function(self, key, val)
          self._settings[key] = val
        end,
      },
      bookmark = {
        getBookmarkedPages = function()
          return {
            [5] = { bookmark = true },
            [15] = { note = true, highlight = true },
          }
        end,
        onPageUpdate = function() end,
      },
      link = {
        getPreviousLocationPages = function()
          return { [12] = 1 }
        end,
        addCurrentLocationToStack = function() end,
      },
      handmade = {
        isHandmadeTocEnabled = function()
          return false
        end,
      },
      statistics = {
        isEnabled = function()
          return true
        end,
        getCurrentBookReadPages = function()
          return {
            [1] = { 0.5, 100 },
            [2] = { 0.8, 50 },
          }
        end,
        start_current_period = os.time() - 300,
      },
      pagemap = {
        wantsPageLabels = function()
          return false
        end,
        cleanPageLabel = function(self, l)
          return l
        end,
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

  it("should require BookMapWidget module and subwidget", function()
    assert.is_table(BookMapWidget)
    assert.is_function(BookMapWidget.new)
    assert.is_table(BookMapRow)
  end)

  describe("BookMapRow subwidget", function()
    it("should calculate spacing and page coordinates correctly", function()
      local font_face = Font:getFace("infofont", 14)
      local spacing = BookMapRow:getLeftSpacingForNumberOfPageSlots(5, 20, 400)
      assert.is_number(spacing)

      local row = BookMapRow:new({
        width = 400,
        height = 60,
        left_spacing = 20,
        span_height = 15,
        font_face = font_face,
        start_page_text = "1",
        start_page = 1,
        end_page = 20,
        pages_per_row = 20,
        cur_page = 10,
        toc_items = {
          [1] = {
            {
              title = "Chap 1",
              p_start = 1,
              p_end = 10,
              seq_in_level = 1,
            },
          },
        },
        bookmarked_pages = { [5] = { bookmark = true } },
        previous_locations = { [8] = 1 },
        hidden_flows = {},
        read_pages = { [1] = { 0.5, 100 } },
      })

      assert.is_table(row)
      assert.is_number(row.page_slot_width)

      local x1 = row:getPageX(1)
      local x20_end = row:getPageX(20, true)
      assert.is_number(x1)
      assert.is_number(x20_end)
      assert.is_true(x20_end > x1)

      -- Test getPageAtX
      local page_at_x = row:getPageAtX(row.pages_frame_offset_x + 5)
      assert.is_number(page_at_x)
      assert.are.equal(1, page_at_x)

      -- Test bounds behavior
      assert.is_nil(row:getPageAtX(-10, false))
      assert.are.equal(1, row:getPageAtX(-10, true))

      assert.is_nil(row:getPageAtX(row.pages_frame_inner_width + 100, false))
      assert.are.equal(
        20,
        row:getPageAtX(row.pages_frame_inner_width + 100, true)
      )
    end)

    it("should paint BookMapRow without errors", function()
      local font_face = Font:getFace("infofont", 14)
      local row = BookMapRow:new({
        width = 400,
        height = 60,
        left_spacing = 20,
        span_height = 15,
        font_face = font_face,
        alt_theme = true,
        start_page_text = "1",
        start_page = 1,
        end_page = 20,
        pages_per_row = 20,
        cur_page = 10,
        toc_items = {
          [1] = {
            {
              title = "Chap 1",
              p_start = 1,
              p_end = 10,
              seq_in_level = 1,
            },
          },
        },
        bookmarked_pages = {
          [5] = { bookmark = true },
          [10] = { highlight = true, note = true, bookmark = true },
        },
        previous_locations = { [8] = 1 },
        extra_symbols_pages = { [12] = 0x2605 },
        hidden_flows = { { 1, 5 } },
        read_pages = { [1] = { 0.5, 100 } },
        current_session_duration = 200,
        extended_sep_pages = { [10] = 1 },
        page_texts = {
          [15] = { text = "15", block = "left", block_dx = 2 },
        },
      })

      local bb = Blitbuffer.new(400, 60)
      row:paintTo(bb, 0, 0)
    end)
  end)

  describe("BookMapWidget layout & initialization", function()
    it("should initialize BookMapWidget in standard grid mode", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      assert.is_table(widget)
      assert.are.equal(100, widget.nb_pages)
      assert.are.equal(10, widget.cur_page)
      assert.are.equal(10, widget.focus_page)
      assert.is_false(widget.flat_map)
      assert.is_false(widget.overview_mode)
    end)

    it("should initialize BookMapWidget in overview mode", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
        overview_mode = true,
      })

      assert.is_table(widget)
      assert.is_true(widget.overview_mode)
      assert.is_false(widget.flat_map)
    end)

    it("should initialize BookMapWidget in flat map mode", function()
      mock_ui.doc_settings._settings["book_map_flat"] = true
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      assert.is_table(widget)
      assert.is_true(widget.flat_map)
      assert.is_table(widget.flat_toc_depth_faces)
    end)
  end)

  describe("Settings and Layout Updates", function()
    it("should update TOC depth and flat map setting", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      local initial_depth = widget.toc_depth

      -- Decrement TOC depth
      assert.is_true(widget:updateTocDepth(-1))
      assert.are.equal(initial_depth - 1, widget.toc_depth)

      -- Increment TOC depth
      assert.is_true(widget:updateTocDepth(1))
      assert.are.equal(initial_depth, widget.toc_depth)

      -- Try setting same values (returns false)
      assert.is_false(widget:updateTocDepth(0))

      -- Set explicit depth and flat map
      assert.is_true(widget:updateTocDepth(1, true))
      assert.are.equal(1, widget.toc_depth)
      assert.is_true(widget.flat_map)
    end)

    it("should update pages per row", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      local initial_pages = widget.pages_per_row

      assert.is_true(widget:updatePagesPerRow(10, true))
      assert.are.equal(initial_pages + 10, widget.pages_per_row)

      assert.is_true(widget:updatePagesPerRow(-10, true))
      assert.are.equal(initial_pages, widget.pages_per_row)

      -- Clamping to min/max
      widget:updatePagesPerRow(1000, false)
      assert.are.equal(widget.max_pages_per_row, widget.pages_per_row)

      widget:updatePagesPerRow(1, false)
      assert.are.equal(widget.min_pages_per_row, widget.pages_per_row)
    end)

    it("should toggle default settings and save settings", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      widget:toggleDefaultSettings()
      assert.is_number(widget.toc_depth)

      widget:saveSettings(true)
      assert.is_nil(widget.flat_map)
    end)

    it("should update editable stuff", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      widget:updateEditableStuff(true)
      assert.is_true(widget.editable_stuff_edited)
    end)
  end)

  describe("Navigation and Row Lookup", function()
    it("should locate rows by Y coordinates", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      local row = widget:getVGroupRowAtY(10)
      assert.is_table(row)

      local row_near = widget:getBookMapRowNearY(10)
      assert.is_table(row_near)
    end)

    it("should scroll by row and page", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      assert.is_true(widget:onScrollRowDown())
      assert.is_true(widget:onScrollRowUp())
      assert.is_true(widget:onScrollPageDown())
      assert.is_true(widget:onScrollPageUp())
    end)
  end)

  describe("Gesture Event Handling", function()
    it("should handle pan gestures", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      assert.is_true(
        widget:onPan(nil, { mousewheel_direction = true, direction = "north" })
      )
      assert.is_true(
        widget:onPan(nil, { mousewheel_direction = true, direction = "south" })
      )
    end)

    it("should handle pinch and spread gestures", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })

      assert.is_true(widget:onPinch(nil, { direction = "horizontal" }))
      assert.is_true(widget:onPinch(nil, { direction = "vertical" }))
      assert.is_true(widget:onPinch(nil, { direction = "diagonal" }))

      assert.is_true(widget:onSpread(nil, { direction = "horizontal" }))
      assert.is_true(widget:onSpread(nil, { direction = "vertical" }))
      assert.is_true(widget:onSpread(nil, { direction = "diagonal" }))
    end)

    it("should handle swipe and multiswipe gestures", function()
      local Device = require("device")
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      make_mock_window(widget)

      local screen_w = Device.screen:getWidth()
      local screen_h = Device.screen:getHeight()

      -- Left edge swipe for TOC depth
      assert.is_true(widget:onSwipe(nil, {
        direction = "south",
        pos = Geom:new({ x = screen_w * 0.05, y = screen_h * 0.5 }),
      }))
      assert.is_true(widget:onSwipe(nil, {
        direction = "north",
        pos = Geom:new({ x = screen_w * 0.05, y = screen_h * 0.5 }),
      }))

      -- Bottom edge swipe for pages per row
      assert.is_true(widget:onSwipe(nil, {
        direction = "west",
        distance = 100,
        pos = Geom:new({ x = screen_w * 0.5, y = screen_h - 10 }),
      }))
      assert.is_true(widget:onSwipe(nil, {
        direction = "east",
        distance = 100,
        pos = Geom:new({ x = screen_w * 0.5, y = screen_h - 10 }),
      }))

      -- Main area page scrolling swipes
      assert.is_true(widget:onSwipe(nil, {
        direction = "north",
        pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
      }))
      assert.is_true(widget:onSwipe(nil, {
        direction = "south",
        pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
      }))

      -- Diagonal swipe returns false (allows screenshot)
      assert.is_false(widget:onSwipe(nil, {
        direction = "northeast",
        pos = Geom:new({ x = screen_w * 0.5, y = screen_h * 0.5 }),
      }))

      -- MultiSwipe
      assert.is_true(widget:onMultiSwipe())
    end)
  end)

  describe("Tap Event Handling", function()
    it("should handle tap events and launch page browser", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      make_mock_window(widget)

      local tap_y = widget.title_bar_h + 50

      -- Tap inside cropping widget on a row
      assert.is_true(
        widget:onTap(nil, { pos = Geom:new({ x = 200, y = tap_y }) })
      )
      if #UIManager._window_stack > 1 then
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end
    end)

    it(
      "should handle tap event with direct goto page when tap_to_page_browser is false",
      function()
        G_reader_settings:save("book_map_tap_to_page_browser", false)

        local broadcasted_events = {}
        local orig_broadcast = UIManager.broadcastEvent
        UIManager.broadcastEvent = function(self, ev)
          table.insert(broadcasted_events, ev)
        end

        local widget = BookMapWidget:new({
          ui = mock_ui,
        })
        make_mock_window(widget)

        local tap_y = widget.title_bar_h + 50

        assert.is_true(
          widget:onTap(nil, { pos = Geom:new({ x = 200, y = tap_y }) })
        )

        UIManager.broadcastEvent = orig_broadcast

        local found_goto_page = false
        for _, ev in ipairs(broadcasted_events) do
          if type(ev) == "table" and ev.handler == "onGotoPage" then
            found_goto_page = true
            assert.is_number(ev.args[1])
            break
          end
        end
        assert.is_true(found_goto_page)
      end
    )

    it("should ignore taps outside cropping widget", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      make_mock_window(widget)

      -- Tap outside (e.g. above or below)
      assert.is_true(widget:onTap(nil, { pos = Geom:new({ x = 10, y = -50 }) }))
    end)
  end)

  describe("Dialogs, Info screens, and Paint", function()
    it("should display menu and info dialogs", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      make_mock_window(widget)

      widget:onShowBookMapMenu()
      if #UIManager._window_stack > 1 then
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end

      widget:showAbout()
      if #UIManager._window_stack > 1 then
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end

      widget:showGestures()
      if #UIManager._window_stack > 1 then
        UIManager:close(
          UIManager._window_stack[#UIManager._window_stack].widget
        )
      end
    end)

    it("should paint BookMapWidget and hints without errors", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      local bb = Blitbuffer.new(600, 800)
      widget:paintTo(bb, 0, 0)
    end)
  end)

  describe("Hidden Flows and Page Map support", function()
    it(
      "should render correctly with hidden flows and page labels enabled",
      function()
        mock_ui.document.hasHiddenFlows = function()
          return true
        end
        mock_ui.document.flows = { { 1, 10 } }
        mock_ui.document.getPageFlow = function(self, p)
          return p <= 10 and 1 or 0
        end

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
            { page = 10, label = "1" },
          }
        end

        local widget = BookMapWidget:new({
          ui = mock_ui,
        })

        assert.is_table(widget)
        assert.is_table(widget.hidden_flows)
        assert.is_table(widget.page_labels)

        local bb = Blitbuffer.new(600, 800)
        widget:paintTo(bb, 0, 0)
      end
    )
  end)

  describe("Exit behavior", function()
    it("should handle exit without parent callbacks", function()
      local root_exit_called = false
      local widget = BookMapWidget:new({
        ui = mock_ui,
        on_root_exit = function()
          root_exit_called = true
        end,
      })
      make_mock_window(widget)

      assert.is_true(widget:onExit(false))
      assert.is_true(root_exit_called)
    end)

    it("should handle exit with on_exit and on_update callbacks", function()
      local exit_called = false
      local update_called = false
      local widget = BookMapWidget:new({
        ui = mock_ui,
        on_exit = function(close_all)
          exit_called = close_all
        end,
        on_update = function()
          update_called = true
        end,
      })
      make_mock_window(widget)

      widget.editable_stuff_edited = true
      assert.is_true(widget:onExit(false))
      assert.is_true(update_called)

      local widget2 = BookMapWidget:new({
        ui = mock_ui,
        on_exit = function(close_all)
          exit_called = close_all
        end,
      })
      make_mock_window(widget2)
      assert.is_true(widget2:onExit(true))
      assert.is_true(exit_called)
    end)
  end)

  describe("RTL mirrored UI layout support", function()
    local BD

    before_each(function()
      BD = require("ui/bidi")
      stub(BD, "mirroredUILayout", function()
        return true
      end)
    end)

    after_each(function()
      if BD and BD.mirroredUILayout.revert then
        BD.mirroredUILayout:revert()
      end
    end)

    it("should calculate page coordinates correctly in RTL mode for BookMapRow", function()
      local font_face = Font:getFace("infofont", 14)
      local row = BookMapRow:new({
        width = 400,
        height = 60,
        left_spacing = 20,
        span_height = 15,
        font_face = font_face,
        start_page_text = "1",
        start_page = 1,
        end_page = 20,
        pages_per_row = 20,
        cur_page = 10,
        toc_items = {
          [1] = {
            {
              title = "Chap 1",
              p_start = 1,
              p_end = 10,
              seq_in_level = 1,
            },
          },
        },
        bookmarked_pages = {},
        previous_locations = {},
        extra_symbols_pages = {},
        hidden_flows = {},
        read_pages = {},
        page_texts = {},
      })

      assert.is_table(row)
      local x_start = row:getPageX(1)
      local x_end = row:getPageX(20)
      local x_start_right = row:getPageX(1, true)
      local x_middle_right = row:getPageX(10, true)
      assert.is_number(x_start)
      assert.is_number(x_end)
      assert.is_number(x_start_right)
      assert.is_number(x_middle_right)

      local page_at_x = row:getPageAtX(row.pages_frame_offset_x + 5)
      assert.is_number(page_at_x)

      local bb = Blitbuffer.new(400, 60)
      row:paintTo(bb, 0, 0)
    end)

    it("should paint swipe hints correctly in RTL mode for BookMapWidget", function()
      local widget = BookMapWidget:new({
        ui = mock_ui,
      })
      local bb = Blitbuffer.new(600, 800)
      widget:paintTo(bb, 0, 0)

      -- Test last unit in vertical swipe hint
      widget.toc_depth = widget.max_toc_depth
      widget.flat_map = false
      widget.vs_hint_info = nil
      widget:paintLeftVerticalSwipeHint(bb)
      widget:paintBottomHorizontalSwipeHint(bb)
    end)
  end)
end)
