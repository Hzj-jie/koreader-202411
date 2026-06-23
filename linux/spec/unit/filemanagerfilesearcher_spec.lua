describe("filemanagerfilesearcher", function()
  local FileSearcher
  local mock_ffiutil
  local mock_device
  local mock_confirm_box
  local mock_info_message
  local mock_input_dialog
  local mock_menu
  local mock_button_dialog
  local mock_check_button
  local mock_lfs
  local mock_fs
  local mock_ui

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      has = function(self, key)
        return key == "home_dir"
      end,
      read = function(self, key)
        if key == "home_dir" then return "/home/user" end
      end
    }

    mock_fs = {
      ["/"] = {
        { name = "books", mode = "directory" },
      },
      ["/books"] = {
        { name = "book1.epub", mode = "file" },
        { name = "subdir", mode = "directory" },
        { name = ".hidden_file", mode = "file" },
        { name = "unsupported.txt", mode = "file" },
      },
      ["/books/subdir"] = {
        { name = "book2.pdf", mode = "file" },
        { name = "ANOTHER.EPUB", mode = "file" },
      }
    }

    mock_lfs = {
      dir = function(path)
        local items = mock_fs[path] or {}
        local idx = 0
        return function()
          idx = idx + 1
          if items[idx] then
            return items[idx].name
          end
        end
      end,
      attributes = function(path, field)
        local parent, name = path:match("^(.*)/([^/]+)$")
        if parent == "" then parent = "/" end
        local items = mock_fs[parent] or {}
        for _, item in ipairs(items) do
          if item.name == name then
            local attrs = {
              mode = item.mode,
              size = 100,
            }
            if field then return attrs[field] end
            return attrs
          end
        end
        return nil
      end
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

    mock_ffiutil = {
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end
    }
    package.loaded["ffi/util"] = mock_ffiutil

    mock_device = {
      hasKeyboard = function() return true end,
    }
    package.loaded["device"] = mock_device

    package.loaded["docsettings"] = {
      hasSidecarFile = function() return false end,
      open = function() return {} end,
    }

    package.loaded["document/documentregistry"] = {
      hasProvider = function(self, path)
        return path:match("%.epub$") or path:match("%.pdf$") or path:match("%.EPUB$")
      end
    }

    package.loaded["ffi/utf8proc"] = {
      lowercase = function(s) return s:lower() end
    }

    local mock_input_container = {
      extend = function(self, subclass)
        subclass = subclass or {}
        setmetatable(subclass, { __index = self })
        subclass.new = function(cls, ...)
          local inst = setmetatable({ key_events = {} }, { __index = cls })
          if inst.init then inst:init(...) end
          return inst
        end
        return subclass
      end,
      showWidget = require("ui/widget/widget").showWidget,
      uimanagedCleanUp = require("ui/widget/widget").uimanagedCleanUp,
    }
    package.loaded["ui/widget/container/inputcontainer"] = mock_input_container

    package.loaded["ui/trapper"] = {
      wrap = function(self, fn) fn() end,
      dismissableRunInSubprocess = function(self, fn, _info)
        return true, fn()
      end
    }

    package.loaded["ui/widget/filechooser"] = {
      show_hidden = false,
      show_unsupported = false,
      show_dir = function() return true end,
      show_file = function() return true end,
      getCollate = function() return function(a, b) return a < b end end,
      getListItem = function(self, _, f, fullpath, attributes, _collate)
        return { f = f, path = fullpath, attr = attributes, is_file = attributes.mode == "file" }
      end,
      genItemTable = function(self, dirs, files)
        local res = {}
        for _, d in ipairs(dirs) do table.insert(res, d) end
        for _, f in ipairs(files) do table.insert(res, f) end
        return res
      end
    }

    package.loaded["apps/filemanager/filemanagerutil"] = {
      genStatusButtonsRow = function() return { text = "Mock Status Row" } end,
      genResetSettingsButton = function() return { text = "Mock Reset Button" } end,
      genBookInformationButton = function() return { text = "Mock Info Button" } end,
      genShowFolderButton = function() return { text = "Mock Show Folder Button" } end,
    }

    mock_menu = {
      new = spy.new(function(self, args)
        local obj = {
          is_menu = true,
          subtitle = args.subtitle,
          onMenuSelect = args.onMenuSelect,
          onMenuHold = args.onMenuHold,
          ui = args.ui,
          _manager = args._manager,
          switchItemTable = spy.new(function(s, title, item_table, _idx)
            s.title = title
            s.item_table = item_table
          end),
        }
        return obj
      end)
    }
    package.loaded["ui/widget/menu"] = mock_menu

    mock_confirm_box = {
      new = spy.new(function(self, args)
        return {
          is_confirm_box = true,
          text = args.text,
          ok_text = args.ok_text,
          ok_callback = args.ok_callback,
        }
      end)
    }
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    mock_info_message = {
      new = spy.new(function(self, args)
        return {
          is_info_message = true,
          text = args.text,
        }
      end)
    }
    package.loaded["ui/widget/infomessage"] = mock_info_message

    mock_input_dialog = {
      new = spy.new(function(self, args)
        local obj
        obj = {
          is_input_dialog = true,
          title = args.title,
          input = args.input,
          buttons = args.buttons,
          widgets = {},
          addWidget = function(s, w) table.insert(s.widgets, w) end,
          getInputText = function() return obj.mock_input_value or args.input or "" end,
        }
        return obj
      end)
    }
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    mock_button_dialog = {
      new = spy.new(function(self, args)
        return {
          is_button_dialog = true,
          title = args.title,
          buttons = args.buttons,
        }
      end)
    }
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    mock_check_button = {
      new = spy.new(function(self, args)
        return {
          is_check_button = true,
          text = args.text,
          checked = args.checked,
        }
      end)
    }
    package.loaded["ui/widget/checkbutton"] = mock_check_button

    local last_shown_widget
    local last_closed_widget
    package.loaded["ui/uimanager"] = {
      broadcastEvent = spy.new(function() end),
      show = spy.new(function(self, widget)
        last_shown_widget = widget
      end),
      close = spy.new(function(self, widget)
        last_closed_widget = widget
      end),
      forceRepaint = spy.new(function() end),
      getLastShownWidget = function() return last_shown_widget end,
      getLastClosedWidget = function() return last_closed_widget end,
    }

    local mock_gettext = setmetatable({
      ngettext = function(sing, plur, n) return n == 1 and sing or plur end,
    }, {
      __call = function(self, text)
        return text
      end
    })
    package.loaded["gettext"] = mock_gettext

    package.loaded["util"] = {
      fixUtf8 = function(s) return s end,
      stringStartsWith = function(s, prefix) return s:sub(1, #prefix) == prefix end,
      tableSize = function(t)
        local count = 0
        for _ in pairs(t) do count = count + 1 end
        return count
      end,
    }

    mock_ui = {
      file_chooser = setmetatable({
        path = "/books",
        refreshPath = spy.new(function() end),
        changeToPath = spy.new(function() end),
      }, {
        __index = package.loaded["ui/widget/filechooser"]
      }),
      collections = {
        genAddToCollectionButton = function() return { text = "Mock Add to Collection" } end,
      },
      coverbrowser = nil,
      bookinfo = {
        getDocProps = function() return {} end,
        findInProps = function() return false end,
      }
    }

    package.loaded["apps/filemanager/filemanagerfilesearcher"] = nil
    FileSearcher = require("apps/filemanager/filemanagerfilesearcher")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagerfilesearcher"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["device"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["ffi/utf8proc"] = nil
    package.loaded["ui/widget/container/inputcontainer"] = nil
    package.loaded["ui/trapper"] = nil
    package.loaded["ui/widget/filechooser"] = nil
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["ui/widget/menu"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/checkbutton"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    package.loaded["util"] = nil
    _G.G_reader_settings = nil
  end)

  it("should register key events on init if device has keyboard", function()
    local searcher = FileSearcher:new()
    assert.truthy(searcher.key_events.ShowFileSearch)
    assert.truthy(searcher.key_events.ShowFileSearchBlank)
  end)

  describe("onShowFileSearch", function()
    it("should show InputDialog with checkbuttons and handle search trigger", function()
      local searcher = FileSearcher:new()
      searcher.ui = mock_ui

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      searcher:onShowFileSearch("test_query")

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_input_dialog)
      assert.are.equal("Enter text to search for in filename", dialog.title)
      assert.are.equal("test_query", dialog.input)

      -- Check checkbuttons added
      assert.are.equal(2, #dialog.widgets)
      assert.is_true(dialog.widgets[1].is_check_button)
      assert.are.equal("Case sensitive", dialog.widgets[1].text)
      assert.is_true(dialog.widgets[2].is_check_button)
      assert.are.equal("Include subfolders", dialog.widgets[2].text)

      -- Trigger Current folder callback (button 3 in group 1)
      local buttons = dialog.buttons[1]
      assert.are.equal("Current folder", buttons[3].text)

      dialog.mock_input_value = "book"
      dialog.widgets[1].checked = true -- Case sensitive
      dialog.widgets[2].checked = false -- Exclude subfolders

      stub(searcher, "doSearch")
      UIManager.close:clear()

      buttons[3].callback()

      assert.spy(UIManager.close).was.called(1)
      assert.are.equal(dialog, UIManager.getLastClosedWidget())
      assert.are.equal("book", FileSearcher.search_string)
      assert.is_true(searcher.case_sensitive)
      assert.is_false(searcher.include_subfolders)
      assert.are.equal("/books", searcher.path)

      assert.stub(searcher.doSearch).was.called(1)
    end)
  end)

  describe("doSearch", function()
    local searcher

    before_each(function()
      searcher = FileSearcher:new()
      searcher.ui = mock_ui
      FileSearcher.search_hash = nil
      FileSearcher.search_results = nil
    end)

    it("should perform search and show results menu", function()
      searcher.path = "/books"
      FileSearcher.search_string = "book"
      searcher.case_sensitive = false
      searcher.include_subfolders = true
      searcher.include_metadata = false

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      searcher:doSearch()

      -- Trapper shows InfoMessage, then closes it, then shows Menu
      -- Our mock UIManager stores last shown widget, which should be the Menu
      local menu = UIManager.getLastShownWidget()
      assert.is_true(menu.is_menu)
      assert.are.equal("Query: book", menu.subtitle)

      -- Verify results
      -- /books contains: book1.epub (file), subdir (directory), .hidden_file (hidden, ignored), unsupported.txt (ignored since no provider)
      -- /books/subdir contains: book2.pdf (file), ANOTHER.EPUB (file, matches case-insensitive "book" -> no, ANOTHER doesn't match "book")
      -- Wait, ANOTHER.EPUB doesn't match "book".
      -- book1.epub matches "book".
      -- book2.pdf matches "book" (via "book2").
      -- subdir contains "dir", doesn't match "book".
      -- So expected files: /books/book1.epub, /books/subdir/book2.pdf.
      -- Expected dirs: none matching "book" (subdir doesn't match).

      assert.truthy(FileSearcher.search_results)
      assert.are.equal(2, #FileSearcher.search_results)

      -- Check formatted items
      assert.are.equal("book1.epub", FileSearcher.search_results[1].f)
      assert.are.equal("/books/book1.epub", FileSearcher.search_results[1].path)
      assert.is_true(FileSearcher.search_results[1].is_file)

      assert.are.equal("book2.pdf", FileSearcher.search_results[2].f)
      assert.are.equal("/books/subdir/book2.pdf", FileSearcher.search_results[2].path)
      assert.is_true(FileSearcher.search_results[2].is_file)
    end)

    it("should show no results message if no files match", function()
      searcher.path = "/books"
      FileSearcher.search_string = "nomatch"
      searcher.case_sensitive = false
      searcher.include_subfolders = true

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      searcher:doSearch()

      local confirmbox = UIManager.getLastShownWidget()
      assert.is_true(confirmbox.is_confirm_box)
      assert.are.equal("No results for 'nomatch'.", confirmbox.text)
    end)
  end)

  describe("getList scanning logic", function()
    local searcher

    before_each(function()
      searcher = FileSearcher:new()
      searcher.ui = mock_ui
    end)

    it("should find all files with wildcard *", function()
      searcher.path = "/books"
      FileSearcher.search_string = "*"
      searcher.case_sensitive = false
      searcher.include_subfolders = true

      local dirs, files = searcher:getList()

      -- Should find subdir (directory)
      -- Should find book1.epub, book2.pdf, ANOTHER.EPUB (unsupported.txt is excluded unless show_unsupported)
      -- .hidden_file is excluded unless show_hidden
      assert.are.equal(1, #dirs)
      assert.are.equal("subdir", dirs[1][1])

      assert.are.equal(3, #files)
      assert.are.equal("book1.epub", files[1][1])
      assert.are.equal("book2.pdf", files[2][1])
      assert.are.equal("ANOTHER.EPUB", files[3][1])
    end)

    it("should respect case sensitivity", function()
      searcher.path = "/books"
      FileSearcher.search_string = "EPUB"
      searcher.case_sensitive = true
      searcher.include_subfolders = true

      local _, files = searcher:getList()

      -- Should only find ANOTHER.EPUB, not book1.epub
      assert.are.equal(1, #files)
      assert.are.equal("ANOTHER.EPUB", files[1][1])
    end)

    it("should exclude subfolders if include_subfolders is false", function()
      searcher.path = "/books"
      FileSearcher.search_string = "*"
      searcher.case_sensitive = false
      searcher.include_subfolders = false

      local dirs, files = searcher:getList()

      -- Should find subdir in /books
      assert.are.equal(1, #dirs)
      -- Should find book1.epub in /books, but NOT book2.pdf or ANOTHER.EPUB which are in /books/subdir
      assert.are.equal(1, #files)
      assert.are.equal("book1.epub", files[1][1])
    end)
  end)

  describe("showFileDialog", function()
    it("should show ButtonDialog with correct actions for a file", function()
      local searcher = FileSearcher:new()
      searcher.ui = mock_ui

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      local item = {
        f = "book1.epub",
        path = "/books/book1.epub",
        is_file = true,
        idx = 1,
      }

      searcher:showFileDialog(item)

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_button_dialog)
      assert.truthy(dialog.title:find("/books/book1.epub"))

      -- Check buttons structure
      -- dialog.buttons has status row, separator, reset/collection, delete/info, folder/open
      -- Let's count them
      assert.are.equal(5, #dialog.buttons)

      -- Row 1: Status buttons row (mocked as a table/button)
      assert.are.equal("Mock Status Row", dialog.buttons[1].text)

      -- Row 3: Reset and Collection
      assert.are.equal("Mock Reset Button", dialog.buttons[3][1].text)
      assert.are.equal("Mock Add to Collection", dialog.buttons[3][2].text)

      -- Row 4: Delete and Info
      assert.are.equal("Delete", dialog.buttons[4][1].text)
      assert.are.equal("Mock Info Button", dialog.buttons[4][2].text)

      -- Row 5: Show Folder and Open
      assert.are.equal("Mock Show Folder Button", dialog.buttons[5][1].text)
      assert.are.equal("Open", dialog.buttons[5][2].text)
    end)
  end)

  describe("uimanagedCleanUp", function()
    it("closes search_menu automatically", function()
      local fs = FileSearcher:new()
      local dummy_menu = { name = "dummy_menu" }
      local stub = require("luassert.stub")
      local UIManager = require("ui/uimanager")

      stub(UIManager, "closeIfShown")

      fs:showWidget(dummy_menu)
      fs.search_menu = dummy_menu

      fs:uimanagedCleanUp()

      assert.is_nil(fs.search_menu)
      assert.stub(UIManager.closeIfShown).was_called_with(UIManager, dummy_menu)

      UIManager.closeIfShown:revert()
    end)
  end)

  describe("close behavior", function()
    local searcher
    local UIManager

    before_each(function()
      searcher = FileSearcher:new()
      searcher.ui = mock_ui
      FileSearcher.search_string = "book"
      FileSearcher.search_results = {
        { f = "book1.epub", path = "/books/book1.epub", is_file = true, idx = 1 }
      }
      UIManager = require("ui/uimanager")
      mock_ui.file_chooser.refreshPath:clear()
    end)

    it("should NOT refresh path on close if not modified", function()
      searcher:onShowSearchResults(false)
      local menu = UIManager.getLastShownWidget()
      assert.truthy(menu.close_callback)

      menu.close_callback()

      assert.spy(mock_ui.file_chooser.refreshPath).was.called(0)
    end)

    it("should refresh path on close if modified (deleted file)", function()
      searcher:onShowSearchResults(false)
      local menu = UIManager.getLastShownWidget()
      assert.truthy(menu.close_callback)

      local item = FileSearcher.search_results[1]
      searcher:showFileDialog(item)
      local dialog = UIManager.getLastShownWidget()

      local delete_btn = dialog.buttons[4][1]
      assert.are.equal("Delete", delete_btn.text)

      package.loaded["apps/filemanager/filemanager"] = {
        showDeleteFileDialog = function(self, file, callback)
          callback()
        end
      }

      delete_btn.callback()

      assert.is_true(searcher.modified)

      menu.close_callback()

      assert.spy(mock_ui.file_chooser.refreshPath).was.called(1)

      package.loaded["apps/filemanager/filemanager"] = nil
    end)

    it("should refresh path on 'Select in file browser' even if not modified", function()
      searcher:onShowSearchResults(false)
      searcher.search_menu.setTitleBarLeftIcon = spy.new(function() end)

      -- Mock title_bar
      mock_ui.title_bar = {
        setRightIcon = spy.new(function() end)
      }

      searcher:setSelectMode()
      assert.truthy(searcher.selected_files)

      local item = FileSearcher.search_results[1]
      local mock_menu_inst = {
        _manager = searcher
      }
      searcher.onMenuHold(mock_menu_inst, item)
      assert.truthy(searcher.selected_files[item.path])

      searcher:setSelectMode()
      local select_dialog = UIManager.getLastShownWidget()

      local select_btn = select_dialog.buttons[2][2]
      assert.are.equal("Select in file browser", select_btn.text)

      select_btn.callback()

      assert.spy(mock_ui.file_chooser.refreshPath).was.called(1)
      assert.spy(mock_ui.title_bar.setRightIcon).was.called(1)

      -- Cleanup mock
      mock_ui.title_bar = nil
    end)
  end)
end)
