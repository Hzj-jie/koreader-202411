describe("ReaderStatus module", function()
  local ReaderStatus, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderStatus = require("apps/reader/modules/readerstatus")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize status module and populate main menu", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local status = readerui.status
    assert.is_table(status)

    local menu_items = {}
    status:addToMainMenu(menu_items)
    assert.is_table(menu_items.book_status)

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Status Actions & Navigation", function()
    it("should handle dispatcher actions registration", function()
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
      }
      local status = ReaderStatus:new({ ui = mock_ui })

      if type(status.onDispatcherRegisterActions) == "function" then
        status:onDispatcherRegisterActions()
      end
    end)

    it("should handle book marking", function()
      local mock_doc_settings = {
        readTableRef = function() return { status = "reading" } end,
        save = function() end,
        flush = function() end,
      }
      local mock_ui = {
        menu = { registerToMainMenu = function() end },
        doc_settings = mock_doc_settings,
        setBookmarkStatus = function() end,
      }
      local status = ReaderStatus:new({ ui = mock_ui })

      if type(status.markBook) == "function" then
        status:markBook(true)
      end
    end)
  end)
end)
