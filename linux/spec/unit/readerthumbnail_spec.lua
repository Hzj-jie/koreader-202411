describe("ReaderThumbnail module", function()
  local ReaderThumbnail

  setup(function()
    require("commonrequire")
    ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local registered = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self_menu, _target)
          registered = true
        end,
      },
      document = {},
    }

    local thumbnail = ReaderThumbnail:new({
      ui = mock_ui,
    })

    assert.is_not_nil(thumbnail)
    assert.is_true(registered)
  end)
end)

describe("ReaderThumbnail module", function()
  local ReaderThumbnail, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))
    ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize thumbnail module and add items to main menu", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local thumbnail = readerui.thumbnail
    assert.is_table(thumbnail)

    local menu_items = {}
    thumbnail:addToMainMenu(menu_items)
    assert.is_table(menu_items.book_map)

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Capabilities & Actions", function()
    it("should setup color, cache, and collect subprocess pids", function()
      local mock_ui = {
        document = {
          info = { number_of_pages = 100 },
          render_color = false,
        },
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local thumb = ReaderThumbnail:new({
        ui = mock_ui,
      })

      thumb:setupColor()
      thumb:setupCache()

      assert.is_table(thumb.tile_cache)
      assert.is_boolean(thumb:collectPids())
    end)

    it("should manage thumbnail requests and cancellation", function()
      local mock_ui = {
        document = {
          info = { number_of_pages = 10 },
          getPageCount = function()
            return 10
          end,
          render_color = false,
        },
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local thumb = ReaderThumbnail:new({
        ui = mock_ui,
        thumbnails_requests = {},
      })

      thumb:setupCache()
      thumb:logCacheSize()

      -- Test removeFromCache & tidyCache
      thumb.current_target_size_tag = "w100_h100"
      thumb:removeFromCache("p1-")
      thumb:removeFromCache({ "p1-", "p2-" }, true)
      thumb:tidyCache()

      -- Test cancelPageThumbnailRequests
      thumb:cancelPageThumbnailRequests("batch_1")
      thumb:cancelPageThumbnailRequests()

      -- Test event handlers
      thumb:onRenderingModeUpdate()
      thumb:onColorRenderingUpdate()
      thumb:onCloseDocument()
      assert.is_nil(thumb.tile_cache)
    end)

    it("should invalidate cached pages for bookmarks with epub documents", function()
      local sample_epub = "spec/front/unit/data/leaves.epub"
      local readerui_epub = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      local thumb_epub = readerui_epub.thumbnail
      thumb_epub:setupCache()

      thumb_epub:resetCachedPagesForBookmarks({
        { page = readerui_epub.rolling:getBookLocation() },
      })
      readerui_epub:onExit()
      readerui_epub:onClose()
    end)

    it("should invalidate cached pages, fetch page images, and get page thumbnails with pdf documents", function()
      local sample_pdf = "spec/front/unit/data/paper.pdf"
      local readerui_pdf = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local thumb_pdf = readerui_pdf.thumbnail
      thumb_pdf:setupCache()

      thumb_pdf:resetCachedPagesForBookmarks({
        { page = 1, pos0 = { page = 1 }, pos1 = { page = 2 } },
      })

      local bb_pdf = thumb_pdf:_getPageImage(1)
      assert.truthy(bb_pdf)

      local req_done = false
      thumb_pdf:getPageThumbnail(
        1,
        80,
        100,
        "batch_pdf",
        function(tile, batch_id, is_delayed)
          req_done = true
        end
      )

      thumb_pdf:cancelPageThumbnailRequests("batch_pdf")
      thumb_pdf:cancelPageThumbnailRequests()

      readerui_pdf:onExit()
      readerui_pdf:onClose()
    end)

    it("should handle show BookMap, PageBrowser, and main menu callbacks with pdf documents", function()
      local sample_pdf = "spec/front/unit/data/paper.pdf"
      local readerui_pdf = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      local thumb_pdf = readerui_pdf.thumbnail
      thumb_pdf:setupCache()

      local shown_widgets = {}
      thumb_pdf.showWidget = function(self, w)
        table.insert(shown_widgets, w)
      end

      thumb_pdf:onShowBookMap(false)
      thumb_pdf:onShowBookMap(true)
      thumb_pdf:onShowPageBrowser()
      assert.are.equal(3, #shown_widgets)

      local menu_items = {}
      thumb_pdf:addToMainMenu(menu_items)
      if menu_items.book_map.callback then
        menu_items.book_map.callback()
      end
      if menu_items.book_map.hold_callback then
        menu_items.book_map.hold_callback()
      end
      if menu_items.page_browser and menu_items.page_browser.callback then
        menu_items.page_browser.callback()
      end

      thumb_pdf._ensureTileGeneration_action(true)
      thumb_pdf._ensureTileGeneration_action(false)
      thumb_pdf._ensureTileGeneration_action(false)
      thumb_pdf._ensureTileGeneration_action(false)

      readerui_pdf:onExit()
      readerui_pdf:onClose()

      local UIManager = require("ui/uimanager")
      while #UIManager._window_stack > 0 do
        UIManager:close(UIManager._window_stack[#UIManager._window_stack].widget)
      end
      UIManager._task_queue = {}
      UIManager._next_tick_tasks = {}
      UIManager._tick_after_next_tasks = {}
    end)
  end)
end)

