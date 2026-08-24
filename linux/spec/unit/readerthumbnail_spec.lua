describe("ReaderThumbnail module", function()
  local ReaderThumbnail, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
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

    it("should handle bookmark cache invalidation for epub and pdf", function()
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

      -- Test _getPageImage
      local bb_pdf = thumb_pdf:_getPageImage(1)
      assert.truthy(bb_pdf)

      readerui_pdf:onExit()
      readerui_pdf:onClose()
    end)
  end)
end)
