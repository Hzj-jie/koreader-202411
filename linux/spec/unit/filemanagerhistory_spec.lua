describe("FileManagerHistory", function()
  local FileManagerHistory
  local mock_widget_container = {}
  local mock_menu = {}
  local mock_uimanager = {}
  local mock_gettext = {}
  local mock_readhistory = {}
  local mock_filemanagerutil = {}
  local mock_docsettings = {}
  local mock_readcollection = {}
  local mock_button_dialog = {}
  local mock_check_button = {}
  local mock_confirm_box = {}
  local mock_input_dialog = {}
  local mock_utf8proc = {}
  local mock_settings

  local function clear_table(t)
    for k in pairs(t) do
      t[k] = nil
    end
    setmetatable(t, nil)
  end

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    print("!!! before_each, mock_uimanager:", mock_uimanager)
    -- Reset/setup mocks in persistent tables
    mock_settings = {
      history_filter = "all",
      history_freeze_finished_books = false,
    }
    _G.G_reader_settings = {
      read = spy.new(function(self, key)
        return mock_settings[key]
      end),
      nilOrTrue = spy.new(function(self, key)
        return mock_settings[key]
      end),
      save = spy.new(function(self, key, val)
        mock_settings[key] = val
      end),
    }

    clear_table(mock_widget_container)
    mock_widget_container.extend = function(self, obj)
      obj = obj or {}
      setmetatable(obj, { __index = self })
      return obj
    end
    mock_widget_container.new = function(self, obj)
      obj = obj or {}
      setmetatable(obj, { __index = self })
      if obj.init then
        obj:init()
      end
      return obj
    end
    package.loaded["ui/widget/container/widgetcontainer"] = mock_widget_container

    clear_table(mock_menu)
    mock_menu.new = function(self, args)
      args = args or {}
      setmetatable(args, { __index = self })
      return args
    end
    mock_menu.switchItemTable = spy.new(function(self, _nil, item_table, _minus_one, _nil2, subtitle)
      self.item_table = item_table
      self.subtitle = subtitle
    end)
    mock_menu.registerToMainMenu = spy.new(function(self, manager)
      self.registered_manager = manager
    end)
    mock_menu.updateItems = spy.new(function(self) end)
    package.loaded["ui/widget/menu"] = mock_menu

    clear_table(mock_uimanager)
    local shown_widgets = {}
    mock_uimanager.show = spy.new(function(self, widget)
      print("!!! Spy show called, self is:", self, "widget is:", widget)
      table.insert(shown_widgets, widget)
    end)
    print("!!! Created spy mock_uimanager.show:", mock_uimanager.show)
    mock_uimanager.close = spy.new(function(self, widget)
      for i, w in ipairs(shown_widgets) do
        if w == widget then
          table.remove(shown_widgets, i)
          break
        end
      end
    end)
    mock_uimanager.runWith = spy.new(function(self, func, _msg)
      func()
    end)
    package.loaded["ui/uimanager"] = mock_uimanager

    clear_table(mock_gettext)
    mock_gettext.pgettext = function(_, text) return text end
    mock_gettext.ngettext = function(sing, plur, n) return n == 1 and sing or plur end
    setmetatable(mock_gettext, {
      __call = function(_, text) return text end,
    })
    package.loaded["gettext"] = mock_gettext

    clear_table(mock_readhistory)
    mock_readhistory.hist = {
      { file = "/path/to/book1.epub", text = "Book 1", dim = false },
      { file = "/path/to/book2.epub", text = "Book 2", dim = false },
      { file = "/path/to/book3.epub", text = "Book 3", dim = true },
    }
    mock_readhistory.removeItem = spy.new(function(self, item, _index)
      for i, v in ipairs(self.hist) do
        if v.file == item.file then
          table.remove(self.hist, i)
          break
        end
      end
    end)
    mock_readhistory.clearMissing = spy.new(function(self)
      for i = #self.hist, 1, -1 do
        if self.hist[i].dim then
          table.remove(self.hist, i)
        end
      end
    end)
    package.loaded["readhistory"] = mock_readhistory

    clear_table(mock_filemanagerutil)
    mock_filemanagerutil.getStatus = spy.new(function(file)
      if file == "/path/to/book1.epub" then
        return "reading"
      elseif file == "/path/to/book2.epub" then
        return "complete"
      end
      return "new"
    end)
    mock_filemanagerutil.genStatusButtonsRow = spy.new(function(_doc_settings, callback)
      return { type = "status_row", callback = callback }
    end)
    mock_filemanagerutil.genResetSettingsButton = spy.new(function(_doc_settings, callback, _is_currently_opened)
      return { type = "reset_button", callback = callback }
    end)
    mock_filemanagerutil.genShowFolderButton = spy.new(function(_file, callback, _dim)
      return { type = "show_folder", callback = callback }
    end)
    mock_filemanagerutil.genBookInformationButton = spy.new(function(_doc_settings, _book_props, callback, _dim)
      return { type = "book_info", callback = callback }
    end)
    mock_filemanagerutil.genBookCoverButton = spy.new(function(_file, _book_props, callback, _dim)
      return { type = "book_cover", callback = callback }
    end)
    mock_filemanagerutil.genBookDescriptionButton = spy.new(function(_file, _book_props, callback, _dim)
      return { type = "book_description", callback = callback }
    end)
    package.loaded["apps/filemanager/filemanagerutil"] = mock_filemanagerutil

    clear_table(mock_docsettings)
    mock_docsettings.hasSidecarFile = spy.new(function(self, _file)
      return false
    end)
    mock_docsettings.open = spy.new(function(self, _file)
      return {
        read = function() return nil end,
      }
    end)
    package.loaded["docsettings"] = mock_docsettings

    clear_table(mock_readcollection)
    mock_readcollection.isFileInCollections = spy.new(function(self, _file)
      return false
    end)
    mock_readcollection.isFileInCollection = spy.new(function(self, _file, _name)
      return false
    end)
    package.loaded["readcollection"] = mock_readcollection

    clear_table(mock_button_dialog)
    mock_button_dialog.new = spy.new(function(self, args)
      local dialog = {
        is_button_dialog = true,
        title = args.title,
        buttons = args.buttons,
      }
      print("!!! ButtonDialog:new called, returning:", dialog)
      return dialog
    end)
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    clear_table(mock_check_button)
    mock_check_button.new = spy.new(function(self, args)
      return {
        is_check_button = true,
        text = args.text,
        checked = args.checked,
      }
    end)
    package.loaded["ui/widget/checkbutton"] = mock_check_button

    clear_table(mock_confirm_box)
    mock_confirm_box.new = spy.new(function(self, args)
      return {
        is_confirm_box = true,
        text = args.text,
        ok_callback = args.ok_callback,
      }
    end)
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    clear_table(mock_input_dialog)
    mock_input_dialog.new = spy.new(function(self, args)
      return {
        is_input_dialog = true,
        title = args.title,
        input = args.input,
        buttons = args.buttons,
        addWidget = function() end,
        getInputText = function(s) return s.input_text or s.input or "" end,
      }
    end)
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    clear_table(mock_utf8proc)
    mock_utf8proc.lowercase = spy.new(function(str)
      return string.lower(str)
    end)
    package.loaded["ffi/utf8proc"] = mock_utf8proc

    package.loaded["ui/bidi"] = {
      filename = function(p) return p end,
    }

    FileManagerHistory = require("apps/filemanager/filemanagerhistory")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagerhistory"] = nil
    package.loaded["ui/widget/container/widgetcontainer"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    package.loaded["readhistory"] = nil
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["readcollection"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/checkbutton"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ffi/utf8proc"] = nil
    package.loaded["ui/bidi"] = nil
    _G.G_reader_settings = nil
  end)


  describe("init", function()
    it("registers to main menu on init", function()
      local ui_mock = { menu = mock_menu }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      assert.spy(mock_menu.registerToMainMenu).was_called(1)
      assert.is_equal(fmh, mock_menu.registered_manager)
    end)
  end)

  describe("addToMainMenu", function()
    it("adds history callback to menu_items", function()
      local ui_mock = { menu = mock_menu }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      local menu_items = {}
      fmh:addToMainMenu(menu_items)
      assert.is_not_nil(menu_items.history)
      assert.is_equal("History", menu_items.history.text)

      fmh.onShowHist = spy.new(function() end)
      menu_items.history.callback()

      assert.spy(mock_uimanager.runWith).was_called(1)
      assert.spy(fmh.onShowHist).was_called(1)
    end)
  end)

  describe("fetchStatuses", function()
    it("populates item.status and counts correctly", function()
      local ui_mock = {
        menu = mock_menu,
        document = { file = "/path/to/book1.epub" },
        doc_settings = {
          readTableRef = function(self, key)
            if key == "summary" then
              return { status = "reading" }
            end
            return {}
          end,
        },
      }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.count = {
        all = 3,
        reading = 0,
        abandoned = 0,
        complete = 0,
        deleted = 0,
        new = 0,
      }

      fmh:fetchStatuses(true)

      assert.is_true(fmh.statuses_fetched)

      -- mock_readhistory.hist has 3 books:
      -- 1: file="/path/to/book1.epub", dim=false (currently open, status="reading")
      -- 2: file="/path/to/book2.epub", dim=false (not open, filemanagerutil.getStatus returns "complete")
      -- 3: file="/path/to/book3.epub", dim=true  (dim=true, status="deleted")

      assert.is_equal("reading", mock_readhistory.hist[1].status)
      assert.is_equal("complete", mock_readhistory.hist[2].status)
      assert.is_equal("deleted", mock_readhistory.hist[3].status)

      assert.is_equal(1, fmh.count.reading)
      assert.is_equal(1, fmh.count.complete)
      assert.is_equal(1, fmh.count.deleted)
    end)
  end)

  describe("updateItemTable", function()
    local fmh
    local hist_menu

    before_each(function()
      hist_menu = mock_menu:new()
      local ui_mock = {
        menu = mock_menu,
        bookinfo = {
          getDocProps = spy.new(function(_file) return {} end),
          findInProps = spy.new(function() return false end),
        },
      }
      fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.hist_menu = hist_menu
      fmh.filter = "all"
    end)

    it("populates hist_menu with all items when no filters are set", function()
      fmh:fetchStatuses(false)
      fmh:updateItemTable()

      assert.spy(hist_menu.switchItemTable).was_called(1)
      local items = hist_menu.item_table
      assert.is_equal(3, #items)
      assert.is_equal("Book 1", items[1].text)
      assert.is_equal("Book 2", items[2].text)
      assert.is_equal("Book 3", items[3].text)
    end)

    it("filters by status", function()
      fmh.filter = "complete"
      fmh:fetchStatuses(false)
      fmh:updateItemTable()

      local items = hist_menu.item_table
      assert.is_equal(1, #items)
      assert.is_equal("Book 2", items[1].text)
    end)

    it("filters by search string matching filename", function()
      fmh.search_string = "book 1"
      fmh:fetchStatuses(false)
      fmh:updateItemTable()

      local items = hist_menu.item_table
      assert.is_equal(1, #items)
      assert.is_equal("Book 1", items[1].text)
    end)
  end)

  describe("onMenuChoice", function()
    it("switches document if a document is currently open", function()
      local ui_mock = {
        menu = mock_menu,
        document = { file = "/path/to/different_book.epub" },
        switchDocument = spy.new(function() end),
        openFile = spy.new(function() end),
      }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh:onMenuChoice({ file = "/path/to/book1.epub" })

      assert.spy(ui_mock.switchDocument).was_called_with(ui_mock, "/path/to/book1.epub")
      assert.spy(ui_mock.openFile).was_not_called()
    end)

    it("opens file if no document is currently open", function()
      local ui_mock = {
        menu = mock_menu,
        switchDocument = spy.new(function() end),
        openFile = spy.new(function() end),
      }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh:onMenuChoice({ file = "/path/to/book1.epub" })

      assert.spy(ui_mock.switchDocument).was_not_called()
      assert.spy(ui_mock.openFile).was_called_with(ui_mock, "/path/to/book1.epub")
    end)
  end)


  describe("onMenuHold", function()
    it("creates and shows a button dialog with actions", function()
      local mock_collections = {
        genAddToCollectionButton = spy.new(function() return { type = "add_to_coll" } end)
      }
      local ui_mock = {
        menu = mock_menu,
        collections = mock_collections,
        document = { file = "/path/to/different_book.epub" },
      }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.filter = "all"
      fmh.hist_menu = mock_menu

      -- Mock Menu context: self is menu, self._manager is fmh
      local menu_context = {
        _manager = fmh,
        ui = ui_mock,
      }

      local item = { file = "/path/to/book1.epub", text = "Book 1", dim = false, idx = 2 }

      -- Call onMenuHold with menu_context as self
      local result = fmh.onMenuHold(menu_context, item)

      assert.is_true(result)
      assert.is_not_nil(menu_context.histfile_dialog)
      assert.spy(mock_button_dialog.new).was_called(1)
      assert.spy(mock_uimanager.show).was_called_with(match.is_ref(mock_uimanager), match.is_ref(menu_context.histfile_dialog))

      -- Let's verify some buttons are present in the dialog buttons structure
      local buttons = menu_context.histfile_dialog.buttons
      -- buttons is a 2D array: table of rows, where each row is a table of buttons
      assert.is_table(buttons)

      -- Row 1: status buttons row (from mock_filemanagerutil.genStatusButtonsRow)
      assert.is_equal("status_row", buttons[1].type)

      -- Row 2: separator (empty table)
      assert.is_table(buttons[2])
      assert.is_equal(0, #buttons[2])

      -- Row 3: genResetSettingsButton and genAddToCollectionButton
      assert.is_equal("reset_button", buttons[3][1].type)
      assert.is_equal("add_to_coll", buttons[3][2].type)

      -- Row 4: Delete and Remove from history
      assert.is_equal("Delete", buttons[4][1].text)
      assert.is_equal("Remove from history", buttons[4][2].text)

      -- Trigger "Remove from history" callback
      local remove_callback = buttons[4][2].callback
      remove_callback()

      assert.spy(mock_readhistory.removeItem).was_called(1)
      -- removeItem should be called with (item, index)
      -- Since fmh.filter is "all" and search_string/selected_collections are nil, index should be item.idx (2)
      assert.spy(mock_readhistory.removeItem).was_called_with(match.is_ref(mock_readhistory), match.is_ref(item), 2)
    end)
  end)

  describe("showHistDialog", function()
    local fmh
    local ui_mock
    local mock_collections
    local shown_dialogs

    before_each(function()
      shown_dialogs = {}
      mock_uimanager.show = spy.new(function(self, widget)
        table.insert(shown_dialogs, widget)
      end)
      mock_uimanager.close = spy.new(function(self, widget)
        for i, w in ipairs(shown_dialogs) do
          if w == widget then
            table.remove(shown_dialogs, i)
            break
          end
        end
      end)

      mock_collections = {
        onShowCollList = spy.new(function(self, _selected, _callback, _flag)
          -- We can manually trigger callback in the test
        end)
      }

      ui_mock = {
        menu = mock_menu,
        collections = mock_collections,
      }
      fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.hist_menu = mock_menu
      fmh.filter = "all"
      fmh.count = {
        all = 3,
        reading = 0,
        abandoned = 0,
        complete = 0,
        deleted = 0,
        new = 0,
      }
    end)

    it("creates filter dialog with status filter buttons", function()
      -- Count.deleted is 1 since mock_readhistory.hist has 3 items and 1 is dim=true
      fmh:showHistDialog()

      assert.spy(mock_button_dialog.new).was_called(1)
      local hist_dialog = shown_dialogs[1]
      assert.is_not_nil(hist_dialog)
      assert.is_equal("Filter by book status", hist_dialog.title)

      local buttons = hist_dialog.buttons
      -- Row 1: all, new, deleted
      assert.is_equal("All (3)", buttons[1][1].text)
      assert.is_equal("New (0)", buttons[1][2].text)
      assert.is_equal("Deleted (1)", buttons[1][3].text)

      -- Row 2: reading, abandoned, complete
      assert.is_equal("Reading (1)", buttons[2][1].text)
      assert.is_equal("On hold (0)", buttons[2][2].text)
      assert.is_equal("Finished (1)", buttons[2][3].text)

      -- Row 3: Filter by collections
      assert.is_equal("Filter by collections", buttons[3][1].text)

      -- Row 4: Search
      assert.is_equal("Search in filename and book metadata", buttons[4][1].text)

      -- Since count.deleted = 1 > 0, we have:
      -- Row 5: separator (empty table)
      -- Row 6: Clear history of deleted files
      assert.is_table(buttons[5])
      assert.is_equal(0, #buttons[5])
      assert.is_equal("Clear history of deleted files", buttons[6][1].text)

      -- Let's trigger Filter reading callback
      fmh.updateItemTable = spy.new(function() end)
      buttons[2][1].callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(hist_dialog))
      assert.is_equal("reading", fmh.filter)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)

    it("resets other filters when All filter is selected", function()
      fmh.search_string = "test"
      fmh.selected_collections = { test = true }

      fmh:showHistDialog()
      local hist_dialog = shown_dialogs[1]
      local buttons = hist_dialog.buttons

      fmh.updateItemTable = spy.new(function() end)
      buttons[1][1].callback() -- callback for "All"

      assert.is_equal("all", fmh.filter)
      assert.is_nil(fmh.search_string)
      assert.is_nil(fmh.selected_collections)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)

    it("handles Filter by collections callback", function()
      fmh:showHistDialog()
      local hist_dialog = shown_dialogs[1]
      local buttons = hist_dialog.buttons

      fmh.updateItemTable = spy.new(function() end)

      -- Override onShowCollList to execute caller_callback immediately
      mock_collections.onShowCollList = spy.new(function(self, _selected, callback, _flag)
        callback({ collection1 = true })
      end)

      buttons[3][1].callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(hist_dialog))
      assert.spy(mock_collections.onShowCollList).was_called(1)
      assert.is_same({ collection1 = true }, fmh.selected_collections)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)

    it("handles Search in filename and book metadata callback", function()
      fmh.onSearchHistory = spy.new(function() end)

      fmh:showHistDialog()
      local hist_dialog = shown_dialogs[1]
      local buttons = hist_dialog.buttons

      buttons[4][1].callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(hist_dialog))
      assert.spy(fmh.onSearchHistory).was_called(1)
    end)

    it("handles Clear history of deleted files callback", function()
      fmh:showHistDialog()
      local hist_dialog = shown_dialogs[1]
      local buttons = hist_dialog.buttons

      fmh.updateItemTable = spy.new(function() end)

      -- Trigger Clear history callback
      buttons[6][1].callback()

      -- Should show a ConfirmBox
      assert.spy(mock_confirm_box.new).was_called(1)
      local confirmbox = shown_dialogs[2]
      assert.is_not_nil(confirmbox)
      assert.is_equal("Clear history of deleted files?", confirmbox.text)

      -- Trigger ok_callback
      confirmbox.ok_callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(hist_dialog))
      assert.spy(mock_readhistory.clearMissing).was_called(1)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)
  end)

  describe("onSearchHistory", function()
    local fmh
    local ui_mock
    local shown_dialogs

    before_each(function()
      shown_dialogs = {}
      mock_uimanager.show = spy.new(function(self, widget)
        table.insert(shown_dialogs, widget)
      end)
      mock_uimanager.close = spy.new(function(self, widget)
        for i, w in ipairs(shown_dialogs) do
          if w == widget then
            table.remove(shown_dialogs, i)
            break
          end
        end
      end)

      ui_mock = {
        menu = mock_menu,
      }
      fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.search_string = "initial search"
      fmh.case_sensitive = true
    end)

    it("creates and shows search input dialog and case-sensitive checkbutton", function()
      fmh:onSearchHistory()

      assert.spy(mock_input_dialog.new).was_called(1)
      assert.spy(mock_check_button.new).was_called(1)

      local search_dialog = shown_dialogs[1]
      assert.is_not_nil(search_dialog)
      assert.is_equal("Enter text to search history for", search_dialog.title)
      assert.is_equal("initial search", search_dialog.input)

      assert.spy(mock_check_button.new).was_called(1)
      local call = mock_check_button.new.calls[1]
      local args = call.refs[2]
      assert.is_equal("Case sensitive", args.text)
      assert.is_true(args.checked)
      assert.is_equal(search_dialog, args.parent)
      assert.is_function(args.callback)
    end)

    it("handles Cancel button callback", function()
      fmh:onSearchHistory()
      local search_dialog = shown_dialogs[1]

      -- Row 1, Col 1: Cancel button
      local cancel_btn = search_dialog.buttons[1][1]
      assert.is_equal("Cancel", cancel_btn.text)

      cancel_btn.callback()
      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(search_dialog))
    end)

    it("handles Search button callback (case-sensitive, called from History)", function()
      fmh.hist_menu = mock_menu
      fmh.updateItemTable = spy.new(function() end)

      fmh:onSearchHistory()
      local search_dialog = shown_dialogs[1]

      -- Row 1, Col 2: Search button
      local search_btn = search_dialog.buttons[1][2]
      assert.is_equal("Search", search_btn.text)

      -- Set input text in mock
      search_dialog.input_text = "Test Query"
      search_btn.callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, match.is_ref(search_dialog))
      assert.is_equal("Test Query", fmh.search_string)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)

    it("handles Search button callback (case-insensitive, called from History)", function()
      fmh.hist_menu = mock_menu
      fmh.case_sensitive = false
      fmh.updateItemTable = spy.new(function() end)

      fmh:onSearchHistory()
      local search_dialog = shown_dialogs[1]

      local search_btn = search_dialog.buttons[1][2]
      search_dialog.input_text = "Test Query"
      search_btn.callback()

      assert.is_equal("test query", fmh.search_string)
      assert.spy(fmh.updateItemTable).was_called(1)
    end)

    it("handles Search button callback (called from Dispatcher)", function()
      fmh.hist_menu = nil
      fmh.onShowHist = spy.new(function() end)

      fmh:onSearchHistory()
      local search_dialog = shown_dialogs[1]

      local search_btn = search_dialog.buttons[1][2]
      search_dialog.input_text = "Test Query"
      search_btn.callback()

      assert.spy(fmh.onShowHist).was_called_with(fmh, {
        search_string = "Test Query",
        case_sensitive = true,
      })
    end)

    it("handles Case sensitive checkbox callback", function()
      local captured_cb
      local check_widget
      mock_check_button.new = spy.new(function(self, args)
        captured_cb = args.callback
        check_widget = {
          is_check_button = true,
          text = args.text,
          checked = args.checked,
        }
        return check_widget
      end)

      fmh:onSearchHistory()

      assert.is_not_nil(captured_cb)

      check_widget.checked = false
      captured_cb()
      assert.is_false(fmh.case_sensitive)

      check_widget.checked = true
      captured_cb()
      assert.is_true(fmh.case_sensitive)
    end)
  end)

  describe("onBookMetadataChanged", function()
    it("updates history menu items if hist_menu is present", function()
      local ui_mock = { menu = mock_menu }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.hist_menu = mock_menu

      fmh:onBookMetadataChanged()

      assert.spy(mock_menu.updateItems).was_called(1)
    end)

    it("does nothing if hist_menu is nil", function()
      local ui_mock = { menu = mock_menu }
      local fmh = FileManagerHistory:new({ ui = ui_mock })
      fmh.hist_menu = nil

      assert.has_no_errors(function()
        fmh:onBookMetadataChanged()
      end)
    end)
  end)
end)





