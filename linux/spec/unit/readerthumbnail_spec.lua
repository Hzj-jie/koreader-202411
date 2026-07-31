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
          getPageCount = function() return 10 end,
        },
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local thumb = ReaderThumbnail:new({
        ui = mock_ui,
        thumbnails_requests = {},
      })

      if type(thumb.cancelThumbnails) == "function" then
        thumb:cancelThumbnails()
      end
    end)
  end)
end)
