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

    local function createReaderUI()
      local sample_epub = "spec/front/unit/data/leaves.epub"
      return ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
    end

    it("should display book status and toggle reading/complete status", function()
      local readerui = createReaderUI()
      local status = readerui.status
      local UIManager = require("ui/uimanager")

      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      local callback_called = false
      status:onShowBookStatus(function()
        callback_called = true
      end)
      assert.is_true(callback_called)
      assert.is_not_nil(shown_widget)

      -- Mark book as complete
      status:markBook(true)
      local summary = readerui.doc_settings:readTableRef("summary")
      assert.are.equal("complete", summary.status)

      -- Toggle book status
      status:markBook()
      assert.are.equal("reading", summary.status)

      UIManager.show = orig_show
      readerui:onExit()
      readerui:onClose()
    end)

    it("should handle end of book popup and button actions", function()
      local readerui = createReaderUI()
      local status = readerui.status
      local UIManager = require("ui/uimanager")

      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      status:onEndOfBook()
      assert.is_not_nil(shown_widget)

      if shown_widget and shown_widget.buttons then
        for _, row in ipairs(shown_widget.buttons) do
          for _, btn in ipairs(row) do
            if btn.text_func then btn:text_func() end
            if btn.callback then
              pcall(function() btn.callback() end)
            end
          end
        end
      end

      UIManager.show = orig_show
      readerui:onExit()
      readerui:onClose()
    end)

    it("should handle quickstart file and different end_document_action settings", function()
      local readerui = createReaderUI()
      local status = readerui.status
      local UIManager = require("ui/uimanager")

      local orig_show = UIManager.show
      UIManager.show = function() end

      -- Quickstart file end of book
      local QuickStart = require("ui/quickstart")
      local orig_read = G_reader_settings.read
      G_reader_settings.read = function(self, k)
        if k == "lastfile" then return QuickStart.quickstart_filename end
        return orig_read(self, k)
      end
      status:onEndOfBook()

      local actions = {
        "book_status",
        "next_file",
        "goto_beginning",
        "file_browser",
        "mark_read",
        "book_status_file_browser",
        "delete_file",
      }

      for _, act in ipairs(actions) do
        G_reader_settings.read = function(self, k)
          if k == "end_document_action" then return act end
          return orig_read(self, k)
        end
        status:onEndOfBook()
      end

      local orig_collate = G_named_settings.collate
      G_named_settings.collate = function() return "date" end
      G_reader_settings.read = function(self, k)
        if k == "end_document_action" then return "next_file" end
        return orig_read(self, k)
      end
      status:onEndOfBook()
      G_named_settings.collate = orig_collate

      G_reader_settings.read = orig_read
      UIManager.show = orig_show
      readerui:onExit()
      readerui:onClose()
    end)

    it("should handle open next document and delete file workflows", function()
      local readerui = createReaderUI()
      local status = readerui.status
      local UIManager = require("ui/uimanager")

      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      status:onOpenNextDocumentInFolder()

      status:deleteFile()
      assert.is_not_nil(shown_widget)

      UIManager.show = orig_show
      readerui:onExit()
      readerui:onClose()
    end)
  end)
end)
