describe("filemanagerutil", function()
  local filemanagerutil
  local mock_doc_settings
  local mock_ffiutil
  local mock_lfs
  local mock_util

  setup(function()
    require("commonrequire")
  end)

  before_each(function()
    _G.G_reader_settings = {
      nilOrTrue = function(self, key)
        if key == "shorten_home_dir" then
          return true
        end
        return nil
      end,
    }
    _G.G_named_settings = {
      home_dir = function()
        return "/home/user"
      end,
    }

    mock_doc_settings = {
      sidecar_exists = false,
      custom_cover_file = nil,
      custom_metadata_file = nil,
      mock_summary = {},
      instances = {},
      hasSidecarFile = function(self, _file)
        return mock_doc_settings.sidecar_exists
      end,
      findCustomCoverFile = function(self, _file)
        return mock_doc_settings.custom_cover_file
      end,
      findCustomMetadataFile = function(self, _file)
        return mock_doc_settings.custom_metadata_file
      end,
      open = function(self, file)
        if not mock_doc_settings.instances[file] then
          mock_doc_settings.instances[file] = {
            data = {
              annotations = "kept",
              bookmarks = "kept",
              cre_dom_version = "kept",
              last_page = "kept",
              font_size = "deleted",
              style_tweaks = "deleted",
            },
            read = function(self, key)
              if key == "doc_path" then
                return file
              end
              return nil
            end,
            readTableRef = function(self, key)
              if key == "summary" then
                return mock_doc_settings.mock_summary
              end
              return {}
            end,
            save = function(self, key, val)
              if key == "summary" then
                mock_doc_settings.mock_summary = val
              end
            end,
            flush = function(self) end,
            delete = function(self, key)
              self.data[key] = nil
            end,
            purge = spy.new(function(self, _dummy, _data_to_purge) end),
          }
        end
        return mock_doc_settings.instances[file]
      end,
    }
    package.loaded["docsettings"] = mock_doc_settings

    mock_ffiutil = {
      realpath = function(path)
        return "/abs/" .. path
      end,
      template = function(tmpl, ...)
        local args = { ... }
        return tmpl:gsub("%%(%d+)", function(n)
          return tostring(args[tonumber(n)])
        end)
      end,
    }
    package.loaded["ffi/util"] = mock_ffiutil

    mock_lfs = {
      files = {},
      dir = function(_dir_path)
        local idx = 0
        return function()
          idx = idx + 1
          return mock_lfs.files[idx]
        end, {}
      end,
      attributes = function(_filepath, field)
        local attr = {
          mode = "file",
          size = 123,
        }
        if field then
          return attr[field]
        end
        return attr
      end,
    }
    package.loaded["libs/libkoreader-lfs"] = mock_lfs

    mock_util = {
      splitFilePathName = function(path)
        local dir = path:match("^(.*)/") or ""
        local file = path:match("([^/]+)$") or path
        return dir, file
      end,
      splitFileNameSuffix = function(filename)
        local base = filename:match("^(.*)%.") or filename
        local ext = filename:match("%.([^%.]+)$") or ""
        return base, ext
      end,
      arrayContains = function(arr, val)
        for _, v in ipairs(arr) do
          if v == val then
            return true
          end
        end
        return false
      end,
    }
    package.loaded["util"] = mock_util

    package.loaded["ui/bidi"] = {
      dirpath = function(p)
        return p
      end,
      filepath = function(p)
        return p
      end,
      filename = function(p)
        return p
      end,
    }
    package.loaded["device"] = {}
    package.loaded["ui/event"] = {
      new = function(self, name, ...)
        return { name = name, ... }
      end,
    }
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
      getLastShownWidget = function() return last_shown_widget end,
      getLastClosedWidget = function() return last_closed_widget end,
    }
    package.loaded["gettext"] = function(text)
      return text
    end

    local mock_check_button_new_count = 0
    local mock_check_button = {
      new = spy.new(function(self, args)
        mock_check_button_new_count = mock_check_button_new_count + 1
        local res = {
          is_check_button = true,
          text = args.text,
          checked = args.checked,
          enabled = args.enabled,
        }
        return res
      end)
    }
    package.loaded["ui/widget/checkbutton"] = mock_check_button

    local mock_confirm_box_new_count = 0
    local mock_confirm_box = {
      new = spy.new(function(self, args)
        mock_confirm_box_new_count = mock_confirm_box_new_count + 1
        local obj = {
          is_confirm_box = true,
          text = args.text,
          ok_callback = args.ok_callback,
          widgets = {},
          addWidget = function(s, w) table.insert(s.widgets, w) end
        }
        return obj
      end)
    }
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    local mock_button_dialog = {
      new = spy.new(function(self, args)
        return {
          is_button_dialog = true,
          title = args.title,
          buttons = args.buttons,
        }
      end)
    }
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    local mock_path_chooser = {
      new = spy.new(function(self, args)
        return {
          is_path_chooser = true,
          onConfirm = args.onConfirm,
        }
      end)
    }
    package.loaded["ui/widget/pathchooser"] = mock_path_chooser

    local mock_filemanager_bookinfo = {
      show = spy.new(function() end),
      onShowBookCover = spy.new(function() end),
      onShowBookDescription = spy.new(function() end),
      extendProps = spy.new(function(p) return p end),
    }
    package.loaded["apps/filemanager/filemanagerbookinfo"] = mock_filemanager_bookinfo

    local mock_filemanager = {
      instance = {
        file_chooser = {
          changeToPath = spy.new(function() end)
        }
      }
    }
    package.loaded["apps/filemanager/filemanager"] = mock_filemanager

    local mock_readerui = {
      instance = {
        onExit = spy.new(function() end),
        showFileManager = spy.new(function() end),
      }
    }
    package.loaded["apps/reader/readerui"] = mock_readerui

    local mock_readhistory = {
      fileSettingsPurged = spy.new(function() end),
    }
    package.loaded["readhistory"] = mock_readhistory

    package.loaded["apps/filemanager/filemanagerutil"] = nil
    filemanagerutil = require("apps/filemanager/filemanagerutil")
  end)

  after_each(function()
    package.loaded["apps/filemanager/filemanagerutil"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["ffi/util"] = nil
    package.loaded["libs/libkoreader-lfs"] = nil
    package.loaded["util"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["device"] = nil
    package.loaded["ui/event"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["gettext"] = nil
    package.loaded["ui/widget/checkbutton"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/pathchooser"] = nil
    package.loaded["apps/filemanager/filemanagerbookinfo"] = nil
    package.loaded["apps/filemanager/filemanager"] = nil
    package.loaded["apps/reader/readerui"] = nil
    package.loaded["readhistory"] = nil
    _G.G_reader_settings = nil
    _G.G_named_settings = nil
  end)

  describe("abbreviate", function()
    it("should abbreviate home path to 'Home'", function()
      local res = filemanagerutil.abbreviate("/home/user")
      assert.are.equal("Home", res)

      local res_slash = filemanagerutil.abbreviate("/home/user/")
      assert.are.equal("Home", res_slash)
    end)

    it("should abbreviate home sub-paths by removing home prefix", function()
      local res = filemanagerutil.abbreviate("/home/user/books/epub")
      assert.are.equal("books/epub", res)
    end)

    it("should return original path if not home", function()
      local res = filemanagerutil.abbreviate("/other/path")
      assert.are.equal("/other/path", res)
    end)

    it("should return empty string if path is nil", function()
      assert.are.equal("", filemanagerutil.abbreviate(nil))
    end)
  end)

  describe("splitFileNameType", function()
    it("should split standard files correctly", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/mybook.epub")
      assert.are.equal("mybook", name)
      assert.are.equal("epub", ext)
    end)

    it("should split fb2.zip and log.zip files as sub-types", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/test.fb2.zip")
      assert.are.equal("test", name)
      assert.are.equal("fb2.zip", ext)

      local name2, ext2 =
        filemanagerutil.splitFileNameType("/books/debug.log.zip")
      assert.are.equal("debug", name2)
      assert.are.equal("log.zip", ext2)
    end)

    it("should split unsupported zip files normally", function()
      local name, ext = filemanagerutil.splitFileNameType("/books/archive.zip")
      assert.are.equal("archive", name)
      assert.are.equal("zip", ext)
    end)
  end)

  describe("getRandomFile", function()
    it("should return a random file matching match_func", function()
      mock_lfs.files = { "file1.epub", "file2.txt", "dir1" }
      mock_lfs.attributes = function(filepath, field)
        local mode = filepath:match("dir1$") and "directory" or "file"
        if field == "mode" then
          return mode
        end
      end

      local file = filemanagerutil.getRandomFile("/books", function(f)
        return f:match("%.epub$") ~= nil
      end)

      assert.are.equal("/books/file1.epub", file)
    end)

    it("should return nil if no files match", function()
      mock_lfs.files = { "file2.txt" }
      local file = filemanagerutil.getRandomFile("/books", function(f)
        return f:match("%.epub$") ~= nil
      end)
      assert.is_nil(file)
    end)
  end)

  describe("getStatus", function()
    it("should return 'new' if no sidecar file exists", function()
      mock_doc_settings.sidecar_exists = false
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("new", status)
    end)

    it("should return 'reading' if sidecar exists but has no status", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.mock_summary = {}
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("reading", status)
    end)

    it("should return correct status if specified in summary", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.mock_summary = { status = "complete" }
      local status = filemanagerutil.getStatus("book.epub")
      assert.are.equal("complete", status)
    end)
  end)

  describe("saveSummary", function()
    it("should save summary with modified date", function()
      local summary = { progress = 0.5 }
      local doc = filemanagerutil.saveSummary("book.epub", summary)

      assert.truthy(mock_doc_settings.mock_summary.modified)
      assert.are.equal(0.5, mock_doc_settings.mock_summary.progress)
      assert.truthy(doc)
    end)
  end)

  describe("statusToString", function()
    it("should translate statuses to human readable text", function()
      assert.are.equal("Unread", filemanagerutil.statusToString("new"))
      assert.are.equal("Reading", filemanagerutil.statusToString("reading"))
      assert.are.equal("On hold", filemanagerutil.statusToString("abandoned"))
      assert.are.equal("Finished", filemanagerutil.statusToString("complete"))
    end)
  end)

  describe("resetDocumentSettings", function()
    it("should delete non-kept settings from docsettings", function()
      local realpath_called = false
      mock_ffiutil.realpath = function(path)
        realpath_called = true
        return "/abs/" .. path
      end

      local doc_settings = mock_doc_settings:open("/abs/book.epub")
      assert.are.equal("kept", doc_settings.data.annotations)
      assert.are.equal("deleted", doc_settings.data.font_size)

      filemanagerutil.resetDocumentSettings("book.epub")

      assert.is_true(realpath_called)
      assert.are.equal("kept", doc_settings.data.annotations)
      assert.are.equal("kept", doc_settings.data.bookmarks)
      assert.is_nil(doc_settings.data.font_size)
      assert.is_nil(doc_settings.data.style_tweaks)
    end)
  end)

  describe("genStatusButtonsRow", function()
    it("should generate three buttons with checkmark on current status and disabled", function()
      local doc_settings = mock_doc_settings:open("book.epub")
      mock_doc_settings.mock_summary = { status = "reading" }

      local callback_called = false
      local caller_callback = function() callback_called = true end

      local buttons = filemanagerutil.genStatusButtonsRow(doc_settings, caller_callback)

      assert.are.equal(3, #buttons)

      -- Button 1: Reading (should have checkmark and be disabled)
      assert.truthy(buttons[1].text:find("Reading  ✓", 1, true))
      assert.is_false(buttons[1].enabled)

      -- Button 2: On hold
      assert.truthy(buttons[2].text:find("On hold", 1, true))
      assert.is_nil(buttons[2].text:find("✓", 1, true))
      assert.is_true(buttons[2].enabled)

      -- Button 3: Finished
      assert.truthy(buttons[3].text:find("Finished", 1, true))
      assert.is_nil(buttons[3].text:find("✓", 1, true))
      assert.is_true(buttons[3].enabled)

      -- Triggering callback of an enabled button
      local UIManager = require("ui/uimanager")
      UIManager.broadcastEvent:clear()

      buttons[3].callback()

      assert.is_true(callback_called)
      assert.are.equal("complete", mock_doc_settings.mock_summary.status)
      assert.spy(UIManager.broadcastEvent).was.called(1)
    end)

    it("should work when passed a file path string instead of settings object", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.mock_summary = { status = "abandoned" }

      local buttons = filemanagerutil.genStatusButtonsRow("book.epub", function() end)

      assert.are.equal(3, #buttons)
      -- Button 2 is "On hold" status
      assert.truthy(buttons[2].text:find("On hold  ✓", 1, true))
      assert.is_false(buttons[2].enabled)
    end)
  end)

  describe("genResetSettingsButton", function()
    it("should be disabled when no sidecar or custom files exist", function()
      mock_doc_settings.sidecar_exists = false
      mock_doc_settings.custom_cover_file = nil
      mock_doc_settings.custom_metadata_file = nil

      local button = filemanagerutil.genResetSettingsButton("book.epub", function() end)
      assert.is_false(button.enabled)
    end)

    it("should be enabled when sidecar exists", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.custom_cover_file = nil
      mock_doc_settings.custom_metadata_file = nil

      local button = filemanagerutil.genResetSettingsButton("book.epub", function() end)
      assert.is_true(button.enabled)
    end)

    it("should show confirmbox with checkbuttons when clicked", function()
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.custom_cover_file = "/path/cover.jpg"
      mock_doc_settings.custom_metadata_file = "/path/metadata.xml"

      local button = filemanagerutil.genResetSettingsButton("book.epub", function() end)
      assert.is_true(button.enabled)

      local UIManager = require("ui/uimanager")
      UIManager.show:clear()

      button.callback()

      assert.spy(UIManager.show).was.called(1)
      local confirmbox = UIManager.show.calls[1].vals[2]
      assert.is_true(confirmbox.is_confirm_box)
      assert.are.equal(3, #confirmbox.widgets)

      assert.is_true(confirmbox.widgets[1].is_check_button)
      assert.is_true(confirmbox.widgets[1].checked)
      assert.is_true(confirmbox.widgets[1].enabled)

      assert.is_true(confirmbox.widgets[2].is_check_button)
      assert.is_true(confirmbox.widgets[2].checked)
      assert.is_true(confirmbox.widgets[2].enabled)

      assert.is_true(confirmbox.widgets[3].is_check_button)
      assert.is_true(confirmbox.widgets[3].checked)
      assert.is_true(confirmbox.widgets[3].enabled)
    end)

    it("should purge checked settings and trigger callbacks when ok_callback is executed", function()
      local doc_settings = mock_doc_settings:open("book.epub")
      mock_doc_settings.sidecar_exists = true
      mock_doc_settings.custom_cover_file = "/path/cover.jpg"
      mock_doc_settings.custom_metadata_file = "/path/metadata.xml"

      local caller_called = false
      local button = filemanagerutil.genResetSettingsButton(doc_settings, function()
        caller_called = true
      end)

      button.callback()

      local UIManager = require("ui/uimanager")
      local confirmbox = UIManager.getLastShownWidget()

      -- Uncheck custom cover
      assert.are.equal("custom cover image", confirmbox.widgets[2].text)
      confirmbox.widgets[2].checked = false

      -- Trigger ok_callback
      doc_settings.purge:clear()
      UIManager.broadcastEvent:clear()
      local readhistory = require("readhistory")
      readhistory.fileSettingsPurged:clear()

      confirmbox.ok_callback()

      assert.spy(doc_settings.purge).was.called(1)
      local purge_args = doc_settings.purge.calls[1].vals[3]
      assert.is_true(purge_args.doc_settings)
      assert.is_false(purge_args.custom_cover_file)
      assert.are.equal("/path/metadata.xml", purge_args.custom_metadata_file)

      assert.is_true(caller_called)
      assert.spy(readhistory.fileSettingsPurged).was.called(1)
    end)
  end)

  describe("genShowFolderButton", function()
    it("should change path in filemanager if filemanager is active", function()
      local filemanager = require("apps/filemanager/filemanager")
      local caller_called = false
      local button = filemanagerutil.genShowFolderButton("/path/to/book.epub", function()
        caller_called = true
      end)

      filemanager.instance.file_chooser.changeToPath:clear()
      button.callback()

      assert.is_true(caller_called)
      assert.spy(filemanager.instance.file_chooser.changeToPath).was.called(1)
      local args = filemanager.instance.file_chooser.changeToPath.calls[1].vals
      assert.are.equal("/path/to", args[2])
      assert.are.equal("/path/to/book.epub", args[3])
    end)

    it("should switch from reader to filemanager if filemanager is inactive", function()
      local filemanager = require("apps/filemanager/filemanager")
      local readerui = require("apps/reader/readerui")
      local old_instance = filemanager.instance
      filemanager.instance = nil

      local caller_called = false
      local button = filemanagerutil.genShowFolderButton("/path/to/book.epub", function()
        caller_called = true
      end)

      readerui.instance.onExit:clear()
      readerui.instance.showFileManager:clear()

      button.callback()

      assert.is_true(caller_called)
      assert.spy(readerui.instance.onExit).was.called(1)
      assert.spy(readerui.instance.showFileManager).was.called(1)
      local args = readerui.instance.showFileManager.calls[1].vals
      assert.are.equal("/path/to/book.epub", args[2])

      filemanager.instance = old_instance
    end)
  end)

  describe("genBookInformationButton", function()
    it("should call filemanagerbookinfo show on callback", function()
      local bookinfo = require("apps/filemanager/filemanagerbookinfo")
      local caller_called = false
      local button = filemanagerutil.genBookInformationButton("book.epub", { prop = 1 }, function()
        caller_called = true
      end)

      bookinfo.show:clear()
      button.callback()

      assert.is_true(caller_called)
      assert.spy(bookinfo.show).was.called(1)
      local args = bookinfo.show.calls[1].vals
      assert.are.equal("book.epub", args[2])
      assert.are.same({ prop = 1 }, args[3])
    end)
  end)

  describe("genBookCoverButton", function()
    it("should be disabled if book_props says has_cover is false", function()
      local button = filemanagerutil.genBookCoverButton("book.epub", { has_cover = false }, function() end)
      assert.is_false(button.enabled)
    end)

    it("should show cover image on callback", function()
      local bookinfo = require("apps/filemanager/filemanagerbookinfo")
      local caller_called = false
      local button = filemanagerutil.genBookCoverButton("book.epub", { has_cover = true }, function()
        caller_called = true
      end)

      assert.is_true(button.enabled)
      bookinfo.onShowBookCover:clear()
      button.callback()

      assert.is_true(caller_called)
      assert.spy(bookinfo.onShowBookCover).was.called(1)
      local args = bookinfo.onShowBookCover.calls[1].vals
      assert.are.equal("book.epub", args[2])
    end)
  end)

  describe("genBookDescriptionButton", function()
    it("should be disabled if no description in book_props", function()
      local button = filemanagerutil.genBookDescriptionButton("book.epub", { description = nil }, function() end)
      assert.is_false(button.enabled)
    end)

    it("should show description on callback", function()
      local bookinfo = require("apps/filemanager/filemanagerbookinfo")
      local caller_called = false
      local button = filemanagerutil.genBookDescriptionButton("book.epub", { description = "Good book" }, function()
        caller_called = true
      end)

      assert.is_true(button.enabled)
      bookinfo.onShowBookDescription:clear()
      button.callback()

      assert.is_true(caller_called)
      assert.spy(bookinfo.onShowBookDescription).was.called(1)
      local args = bookinfo.onShowBookDescription.calls[1].vals
      assert.are.equal("Good book", args[2])
      assert.are.equal("book.epub", args[3])
    end)
  end)

  describe("showChooseDialog", function()
    it("should show ButtonDialog and show PathChooser on Choose button click", function()
      local UIManager = require("ui/uimanager")
      UIManager.show:clear()
      UIManager.close:clear()

      local callback_called = false
      local caller_callback = function(path)
        callback_called = path
      end

      filemanagerutil.showChooseDialog("Select", caller_callback, "/cur/path", "/def/path", "*.epub")

      assert.spy(UIManager.show).was.called(1)
      local dialog = UIManager.getLastShownWidget()
      assert.is_true(dialog.is_button_dialog)
      assert.are.equal(2, #dialog.buttons)

      -- Button 1: Choose file
      assert.are.equal("Choose file", dialog.buttons[1][1].text)
      -- Button 2: Use default
      assert.are.equal("Use default", dialog.buttons[2][1].text)
      assert.is_true(dialog.buttons[2][1].enabled)

      -- Trigger Choose File callback
      UIManager.show:clear()
      dialog.buttons[1][1].callback()

      assert.spy(UIManager.close).was.called(1)
      assert.are.equal(dialog, UIManager.getLastClosedWidget())

      assert.spy(UIManager.show).was.called(1)
      local path_chooser = UIManager.getLastShownWidget()
      assert.is_true(path_chooser.is_path_chooser)

      -- Trigger path chooser confirm
      path_chooser.onConfirm("/new/path/book.epub")
      assert.are.equal("/new/path/book.epub", callback_called)
    end)

    it("should trigger default path directly on Use Default button click", function()
      local UIManager = require("ui/uimanager")
      UIManager.show:clear()
      UIManager.close:clear()

      local callback_called = false
      local caller_callback = function(path)
        callback_called = path
      end

      filemanagerutil.showChooseDialog("Select", caller_callback, "/cur/path", "/def/path")

      local dialog = UIManager.getLastShownWidget()
      dialog.buttons[2][1].callback()

      assert.spy(UIManager.close).was.called(1)
      assert.are.equal(dialog, UIManager.getLastClosedWidget())
      assert.are.equal("/def/path", callback_called)
    end)
  end)
end)
