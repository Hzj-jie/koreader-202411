describe("BookInfo", function()
  local BookInfo
  local mock_widget_container = {}
  local mock_bidi = {}
  local mock_docsettings = {}
  local mock_document = {}
  local mock_docregistry = {}
  local mock_uimanager = {}
  local mock_utf8proc = {}
  local mock_filemanagerutil = {}
  local mock_gettext = {}
  local mock_button_dialog = {}
  local mock_confirm_box = {}
  local mock_info_message = {}
  local mock_input_dialog = {}
  local mock_text_viewer = {}
  local mock_keyvaluepage = {}
  local mock_imageviewer = {}
  local mock_pathchooser = {}

  local original_lfs_attributes
  local original_lfs_dir
  local original_ffiutil_realpath

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
    local ffiutil = require("ffi/util")
    original_ffiutil_realpath = ffiutil.realpath
    ffiutil.realpath = spy.new(function(path)
      if path:sub(1, 7) == "/books/" or path:sub(1, 7) == "/dummy/" or path == "/books" then
        return path
      end
      return original_ffiutil_realpath(path)
    end)

    -- Safe overriding of lfs attributes
    local real_lfs = require("libs/libkoreader-lfs")
    original_lfs_attributes = real_lfs.attributes
    real_lfs.attributes = spy.new(function(file, field)
      if file:sub(1, 7) == "/dummy/" or file:sub(1, 7) == "/books/" then
        local attr = {
          size = 12345,
          access = 1600000000,
          modification = 1600000000,
          mode = "file",
        }
        if field then
          return attr[field]
        end
        return attr
      end
      return original_lfs_attributes(file, field)
    end)

    original_lfs_dir = real_lfs.dir
    real_lfs.dir = spy.new(function(path)
      if path == "/books" then
        local files = { ".", "..", "file1.epub", "file2.pdf", "subdir" }
        local i = 0
        return function()
          i = i + 1
          return files[i]
        end
      end
      return original_lfs_dir(path)
    end)

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

    clear_table(mock_bidi)
    mock_bidi.filename = function(x) return x end
    mock_bidi.dirpath = function(x) return x end
    mock_bidi.auto = function(x) return x end
    mock_bidi.mirroredUILayout = function() return false end
    mock_bidi.rtlUIText = function() return false end
    mock_bidi.flipIfMirroredUILayout = function(x) return x end
    mock_bidi.ltr = function(x) return x end
    mock_bidi.rtl = function(x) return x end
    package.loaded["ui/bidi"] = mock_bidi

    clear_table(mock_gettext)
    mock_gettext.pgettext = function(_, text) return text end
    mock_gettext.ngettext = function(sing, plur, n) return n == 1 and sing or plur end
    setmetatable(mock_gettext, {
      __call = function(_, text) return text end,
    })
    package.loaded["gettext"] = mock_gettext

    clear_table(mock_uimanager)
    mock_uimanager.show = spy.new(function(self, widget) end)
    mock_uimanager.close = spy.new(function(self, widget) end)
    mock_uimanager.broadcastEvent = spy.new(function(self, event) end)
    package.loaded["ui/uimanager"] = mock_uimanager

    clear_table(mock_docsettings)
    mock_docsettings.findCustomCoverFile = spy.new(function() return nil end)
    mock_docsettings.findCustomMetadataFile = spy.new(function() return nil end)
    mock_docsettings.openSettingsFile = spy.new(function()
      return {
        read = function(self, key) return nil end,
        readTableRef = function(self, key) return {} end,
        save = function(self, key, val) end,
        purge = function(self) end,
        flushCustomMetadata = function(self) end,
      }
    end)
    mock_docsettings.open = spy.new(function()
      return {
        read = function(self, key) return nil end,
      }
    end)
    mock_docsettings.hasSidecarFile = spy.new(function() return false end)
    package.loaded["docsettings"] = mock_docsettings

    clear_table(mock_document)
    mock_document.getProps = spy.new(function(self, stats)
      return {
        title = "Book Title",
        authors = "Book Author",
      }
    end)
    package.loaded["document/document"] = mock_document

    clear_table(mock_docregistry)
    mock_docregistry.openDocument = spy.new(function(self, file)
      return {
        getPageCount = function() return 100 end,
        getProps = function() return { title = "Opened Title", authors = "Opened Author" } end,
        getCoverPageImage = function() return "mock_cover_image" end,
        close = function() end,
      }
    end)
    package.loaded["document/documentregistry"] = mock_docregistry

    clear_table(mock_utf8proc)
    mock_utf8proc.lowercase = function(s) return string.lower(s) end
    package.loaded["ffi/utf8proc"] = mock_utf8proc

    clear_table(mock_button_dialog)
    mock_button_dialog.new = spy.new(function(self, args)
      return {
        is_button_dialog = true,
        title = args.title,
        buttons = args.buttons,
      }
    end)
    package.loaded["ui/widget/buttondialog"] = mock_button_dialog

    clear_table(mock_confirm_box)
    mock_confirm_box.new = spy.new(function(self, args)
      return {
        is_confirm_box = true,
        text = args.text,
        ok_callback = args.ok_callback,
      }
    end)
    package.loaded["ui/widget/confirmbox"] = mock_confirm_box

    clear_table(mock_info_message)
    mock_info_message.new = spy.new(function(self, args)
      return {
        is_info_message = true,
        text = args.text,
      }
    end)
    package.loaded["ui/widget/infomessage"] = mock_info_message

    clear_table(mock_input_dialog)
    mock_input_dialog.new = spy.new(function(self, args)
      return {
        is_input_dialog = true,
        title = args.title,
        input = args.input,
        buttons = args.buttons,
        getInputText = function(s) return s.input_text or s.input or "" end,
        getInputValue = function(s) return s.input_text or s.input or "" end,
      }
    end)
    package.loaded["ui/widget/inputdialog"] = mock_input_dialog

    clear_table(mock_text_viewer)
    mock_text_viewer.new = spy.new(function(self, args)
      return {
        is_text_viewer = true,
        title = args.title,
        text = args.text,
      }
    end)
    package.loaded["ui/widget/textviewer"] = mock_text_viewer

    clear_table(mock_keyvaluepage)
    mock_keyvaluepage.new = spy.new(function(self, args)
      return {
        is_keyvaluepage = true,
        title = args.title,
        kv_pairs = args.kv_pairs,
        close_callback = args.close_callback,
        onExit = spy.new(function() end),
      }
    end)
    package.loaded["ui/widget/keyvaluepage"] = mock_keyvaluepage

    clear_table(mock_imageviewer)
    mock_imageviewer.new = spy.new(function(self, args)
      return {
        is_imageviewer = true,
        image = args.image,
      }
    end)
    package.loaded["ui/widget/imageviewer"] = mock_imageviewer

    clear_table(mock_pathchooser)
    mock_pathchooser.new = spy.new(function(self, args)
      return {
        is_pathchooser = true,
        onConfirm = args.onConfirm,
      }
    end)
    package.loaded["ui/widget/pathchooser"] = mock_pathchooser

    local Device = require("device")
    Device.input.setClipboardText = spy.new(function(text) end)
    Device.input.hasClipboard = function() return true end

    package.loaded["apps/filemanager/filemanagerbookinfo"] = nil
    BookInfo = require("apps/filemanager/filemanagerbookinfo")
  end)

  after_each(function()
    local real_lfs = require("libs/libkoreader-lfs")
    real_lfs.attributes = original_lfs_attributes
    real_lfs.dir = original_lfs_dir

    local ffiutil = require("ffi/util")
    ffiutil.realpath = original_ffiutil_realpath

    package.loaded["apps/filemanager/filemanagerbookinfo"] = nil
    package.loaded["ui/widget/container/widgetcontainer"] = nil
    package.loaded["ui/bidi"] = nil
    package.loaded["gettext"] = nil
    package.loaded["ui/uimanager"] = nil
    package.loaded["docsettings"] = nil
    package.loaded["document/document"] = nil
    package.loaded["document/documentregistry"] = nil
    package.loaded["ffi/utf8proc"] = nil
    package.loaded["ui/widget/buttondialog"] = nil
    package.loaded["ui/widget/confirmbox"] = nil
    package.loaded["ui/widget/infomessage"] = nil
    package.loaded["ui/widget/inputdialog"] = nil
    package.loaded["ui/widget/textviewer"] = nil
    package.loaded["ui/widget/keyvaluepage"] = nil
    package.loaded["ui/widget/imageviewer"] = nil
    package.loaded["ui/widget/pathchooser"] = nil
  end)

  describe("init", function()
    it("registers to main menu if self.document is present", function()
      local mock_menu_registered = {}
      local mock_ui = {
        menu = {
          registerToMainMenu = spy.new(function(self, widget)
            table.insert(mock_menu_registered, widget)
          end)
        }
      }
      local instance = BookInfo:new({
        document = {},
        ui = mock_ui,
      })
      assert.truthy(instance)
      assert.spy(mock_ui.menu.registerToMainMenu).was_called(1)
      assert.are.equal(instance, mock_menu_registered[1])
    end)

    it("does not register to main menu if self.document is absent", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = spy.new(function() end)
        }
      }
      local instance = BookInfo:new({
        ui = mock_ui,
      })
      assert.truthy(instance)
      assert.spy(mock_ui.menu.registerToMainMenu).was_not_called()
    end)
  end)

  describe("addToMainMenu", function()
    it("adds book_info item to menu_items", function()
      local instance = BookInfo:new({})
      instance.onShowBookInfo = spy.new(function() end)

      local menu_items = {}
      instance:addToMainMenu(menu_items)

      assert.truthy(menu_items.book_info)
      assert.are.equal("Book information", menu_items.book_info.text)
      assert.is_function(menu_items.book_info.callback)

      menu_items.book_info.callback()
      assert.spy(instance.onShowBookInfo).was_called(1)
    end)
  end)

  describe("extendProps", function()
    it("merges original props with custom props if filepath is provided", function()
      mock_docsettings.findCustomMetadataFile = spy.new(function(_, filepath)
        if filepath == "/books/file.epub" then
          return "/metadata/file.lua"
        end
      end)
      mock_docsettings.openSettingsFile = spy.new(function(metafile)
        return {
          readTableRef = function(self, key)
            if key == "custom_props" then
              return {
                title = "Custom Title",
                authors = "Custom Author",
              }
            end
            return {}
          end
        }
      end)

      local original_props = {
        title = "Orig Title",
        authors = "Orig Author",
        series = "Orig Series",
        pages = 250,
      }

      local extended = BookInfo.extendProps(original_props, "/books/file.epub")
      assert.are.equal("Custom Title", extended.title)
      assert.are.equal("Custom Author", extended.authors)
      assert.are.equal("Orig Series", extended.series)
      assert.are.equal(250, extended.pages)
    end)

    it("uses filename as display_title if original and custom title is missing", function()
      mock_docsettings.findCustomMetadataFile = spy.new(function() return nil end)

      local original_props = {
        authors = "Orig Author",
      }

      local extended = BookInfo.extendProps(original_props, "/books/mybook.epub")
      assert.is_nil(extended.title)
      assert.are.equal("mybook", extended.display_title)
    end)
  end)

  describe("extract", function()
    it("extracts file attributes and metadata into key-value pairs", function()
      local book_props = {
        title = "Metadata Title",
        authors = "Metadata Author",
        series = "Metadata Series",
        series_index = 3,
        language = "en",
        keywords = "key1, key2",
        description = "My book description",
        pages = 400,
      }

      local instance = BookInfo:new({})
      local kv_pairs, file, values_lang = instance:extract("/books/file.epub", book_props)

      assert.are.equal("/books/file.epub", file)
      assert.are.equal("en", values_lang)
      assert.truthy(kv_pairs)

      -- Let's examine the keys in kv_pairs
      local keys = {}
      local vals = {}
      for _, kv in ipairs(kv_pairs) do
        keys[kv[1]] = kv[2]
        if kv.callback then
          vals[kv[1]] = { val = kv[2], cb = kv.callback, hold_cb = kv.hold_callback }
        else
          vals[kv[1]] = kv[2]
        end
      end

      assert.are.equal("file.epub", keys["Filename:"])
      assert.are.equal("EPUB", keys["Format:"])
      assert.are.equal("12.3 kB (12,345 bytes)", keys["Size:"])
      assert.are.equal("2020-09-13 05:26:40", keys["Last open:"])
      assert.are.equal("2020-09-13 05:26:40", keys["File date:"])
      assert.are.equal("/books/", keys["Folder:"])

      assert.are.equal("Tap to display", vals["Cover image:"].val)
      assert.is_function(vals["Cover image:"].cb)
      assert.is_function(vals["Cover image:"].hold_cb)

      assert.are.equal("Metadata Title", keys["Title:"])
      assert.are.equal("Metadata Author", keys["Author(s):"])
      assert.are.equal("Metadata Series", keys["Series:"])
      assert.are.equal(3, keys["Series index:"])
      assert.are.equal("en", keys["Language:"])
      assert.are.equal("key1, key2", keys["Keywords:"])

      assert.are.equal("My book description", vals["Description:"].val)
      assert.is_function(vals["Description:"].cb)

      assert.are.equal(400, keys["Pages:"])
    end)
  end)

  describe("show", function()
    it("instantiates keyvaluepage and shows it via UIManager", function()
      local instance = BookInfo:new({})

      instance:show("/books/file.epub", { title = "Metadata Title" })

      assert.truthy(instance.kvp_widget)
      assert.are.equal("Book information", instance.kvp_widget.title)
      assert.spy(mock_uimanager.show).was_called(1)
      assert.spy(mock_uimanager.show).was_called_with(mock_uimanager, instance.kvp_widget)
    end)

    it("broadcasts invalidation events when closing after metadata update", function()
      local instance = BookInfo:new({})
      instance:show("/books/file.epub", { title = "Metadata Title" })

      instance.prop_updated = {
        filepath = "/books/file.epub",
        doc_props = { title = "Updated Title" },
        metadata_key_updated = "title",
        metadata_value_old = "Metadata Title",
      }

      instance.kvp_widget.close_callback()

      assert.is_nil(instance.custom_doc_settings)
      assert.is_nil(instance.custom_book_cover)

      assert.spy(mock_uimanager.broadcastEvent).was_called(2)
      local call_args1 = mock_uimanager.broadcastEvent.calls[1]
      assert.are.equal("onInvalidateMetadataCache", call_args1.refs[2].handler)
      assert.are.equal("/books/file.epub", call_args1.refs[2].args[1])

      local call_args2 = mock_uimanager.broadcastEvent.calls[2]
      assert.are.equal("onBookMetadataChanged", call_args2.refs[2].handler)
      assert.are.equal(instance.prop_updated, call_args2.refs[2].args[1])
    end)

    it("broadcasts metadata changed when closing after summary update", function()
      local instance = BookInfo:new({})
      instance:show("/books/file.epub", { title = "Metadata Title" })

      instance.summary_updated = true

      instance.kvp_widget.close_callback()

      assert.spy(mock_uimanager.broadcastEvent).was_called(1)
      local call_args = mock_uimanager.broadcastEvent.calls[1]
      assert.are.equal("onBookMetadataChanged", call_args.refs[2].handler)
      assert.is_nil(call_args.refs[2].args[1])
    end)
  end)

  describe("getDocProps", function()
    it("reads from sidecar file (doc_props + doc_pages) if available", function()
      mock_docsettings.hasSidecarFile = spy.new(function() return true end)
      mock_docsettings.open = spy.new(function()
        return {
          read = function(_, key)
            if key == "doc_props" then
              return {
                title = "Sidecar Title",
                authors = "Sidecar Author",
              }
            elseif key == "doc_pages" then
              return 320
            end
          end
        }
      end)

      local props = BookInfo.getDocProps("/books/book.epub")
      assert.are.equal("Sidecar Title", props.title)
      assert.are.equal("Sidecar Author", props.authors)
      assert.are.equal(320, props.pages)
    end)

    it("reads stats if doc_props is missing in sidecar", function()
      mock_docsettings.hasSidecarFile = spy.new(function() return true end)
      mock_docsettings.open = spy.new(function()
        return {
          read = function(_, key)
            if key == "stats" then
              return { pages = 200 }
            elseif key == "doc_pages" then
              return 250
            end
          end
        }
      end)
      mock_document.getProps = spy.new(function(_, stats)
        assert.are.equal(200, stats.pages)
        return {
          title = "Stats Title",
          authors = "Stats Author",
        }
      end)

      local props = BookInfo.getDocProps("/books/book.epub")
      assert.are.equal("Stats Title", props.title)
      assert.are.equal("Stats Author", props.authors)
      assert.are.equal(250, props.pages)
    end)

    it("reads from custom metadata file if sidecar metadata is missing", function()
      mock_docsettings.hasSidecarFile = spy.new(function() return false end)
      mock_docsettings.findCustomMetadataFile = spy.new(function(_, file)
        if file == "/books/book.epub" then
          return "/metadata/book.lua"
        end
      end)
      mock_docsettings.openSettingsFile = spy.new(function(metafile)
        assert.are.equal("/metadata/book.lua", metafile)
        return {
          read = function(_, key)
            if key == "doc_props" then
              return {
                title = "Custom Meta Title",
                authors = "Custom Meta Author",
              }
            end
          end,
          readTableRef = function(_, key)
            return {}
          end
        }
      end)

      local props = BookInfo.getDocProps("/books/book.epub")
      assert.are.equal("Custom Meta Title", props.title)
      assert.are.equal("Custom Meta Author", props.authors)
    end)

    it("opens document directly if all sidecar & custom metadata are missing", function()
      mock_docsettings.hasSidecarFile = spy.new(function() return false end)
      mock_docsettings.findCustomMetadataFile = spy.new(function() return nil end)

      local props = BookInfo.getDocProps("/books/book.epub")
      assert.are.equal("Opened Title", props.title)
      assert.are.equal("Opened Author", props.authors)
      assert.are.equal(100, props.pages)
      assert.spy(mock_docregistry.openDocument).was_called(1)
      assert.spy(mock_docregistry.openDocument).was_called_with(mock_docregistry, "/books/book.epub")
    end)
  end)

  describe("findInProps", function()
    local book_props = {
      title = "The Great Gatsby",
      authors = "F. Scott Fitzgerald",
      series = "Classics",
      series_index = 1,
      description = "<p>A story of <b>wealth</b> and love</p>",
    }

    it("returns true if matched case-insensitively", function()
      local instance = BookInfo:new({})
      assert.truthy(instance:findInProps(book_props, "gatsby", false))
      assert.truthy(instance:findInProps(book_props, "fitzgerald", false))
      assert.truthy(instance:findInProps(book_props, "classics", false))
      assert.truthy(instance:findInProps(book_props, "1", false))
      assert.truthy(instance:findInProps(book_props, "wealth", false))
    end)

    it("returns true for case-sensitive matches if specified", function()
      local instance = BookInfo:new({})
      assert.truthy(instance:findInProps(book_props, "Gatsby", true))
      assert.falsy(instance:findInProps(book_props, "gatsby", true) or false)
    end)

    it("returns false if search string is not found in any properties", function()
      local instance = BookInfo:new({})
      assert.falsy(instance:findInProps(book_props, "dracula", false) or false)
    end)
  end)

  describe("onShowBookDescription", function()
    it("shows description directly if provided", function()
      local instance = BookInfo:new({})
      instance.showBookProp = spy.new(function() end)

      instance:onShowBookDescription("Direct description")
      assert.spy(instance.showBookProp).was_called(1)
      assert.spy(instance.showBookProp).was_called_with(instance, "description", "Direct description")
    end)

    it("extracts description from document if file is provided", function()
      local instance = BookInfo:new({})
      instance.showBookProp = spy.new(function() end)

      mock_docsettings.hasSidecarFile = spy.new(function() return false end)
      mock_docsettings.findCustomMetadataFile = spy.new(function() return nil end)
      mock_docregistry.openDocument = spy.new(function()
        return {
          getPageCount = function() return 100 end,
          getProps = function() return { description = "File description" } end,
          close = function() end,
        }
      end)

      instance:onShowBookDescription(nil, "/books/book.epub")
      assert.spy(instance.showBookProp).was_called(1)
      assert.spy(instance.showBookProp).was_called_with(instance, "description", "File description")
    end)

    it("shows error dialog if description is completely missing", function()
      local instance = BookInfo:new({})
      instance:onShowBookDescription(nil)

      assert.spy(mock_info_message.new).was_called(1)
      local call_args = mock_info_message.new.calls[1]
      assert.are.equal("No book description available.", call_args.refs[2].text)
      assert.spy(mock_uimanager.show).was_called(1)
    end)
  end)

  describe("getCoverImage", function()
    it("returns custom cover image first if force_orig is not true", function()
      local instance = BookInfo:new({})
      mock_docsettings.findCustomCoverFile = spy.new(function(_, file)
        if file == "/books/book.epub" then
          return "/covers/custom_cover.jpg"
        end
      end)
      mock_docregistry.openDocument = spy.new(function(_, file)
        if file == "/covers/custom_cover.jpg" then
          return {
            getCoverPageImage = function() return "custom_cover_data" end,
            close = spy.new(function() end),
          }
        end
      end)

      local cover_data, custom_cover_path = instance:getCoverImage(nil, "/books/book.epub", false)
      assert.are.equal("custom_cover_data", cover_data)
      assert.are.equal("/covers/custom_cover.jpg", custom_cover_path)
    end)

    it("returns original cover image if force_orig is true", function()
      local instance = BookInfo:new({})
      mock_docsettings.findCustomCoverFile = spy.new(function(_, file)
        if file == "/books/book.epub" then
          return "/covers/custom_cover.jpg"
        end
      end)
      mock_docregistry.openDocument = spy.new(function(_, file)
        if file == "/books/book.epub" then
          return {
            getCoverPageImage = function() return "orig_cover_data" end,
            close = spy.new(function() end),
          }
        end
      end)

      local cover_data = instance:getCoverImage(nil, "/books/book.epub", true)
      assert.are.equal("orig_cover_data", cover_data)
    end)
  end)

  describe("onShowBookCover", function()
    it("shows cover image in ImageViewer if available", function()
      local instance = BookInfo:new({})
      instance.getCoverImage = spy.new(function() return "my_cover_image" end)

      instance:onShowBookCover("/books/book.epub")
      assert.spy(mock_imageviewer.new).was_called(1)
      local call_args = mock_imageviewer.new.calls[1]
      assert.are.equal("my_cover_image", call_args.refs[2].image)
      assert.falsy(call_args.refs[2].with_title_bar)
      assert.truthy(call_args.refs[2].fullscreen)
      assert.spy(mock_uimanager.show).was_called(1)
    end)

    it("shows error message if cover image is not available", function()
      local instance = BookInfo:new({})
      instance.getCoverImage = spy.new(function() return nil end)

      instance:onShowBookCover("/books/book.epub")
      assert.spy(mock_info_message.new).was_called(1)
      local call_args = mock_info_message.new.calls[1]
      assert.are.equal("No cover image available.", call_args.refs[2].text)
      assert.spy(mock_uimanager.show).was_called(1)
    end)
  end)

  describe("setCustomCover", function()
    local original_os_remove

    before_each(function()
      original_os_remove = os.remove
      os.remove = spy.new(function() return true end)
      mock_docsettings.removeSidecarDir = spy.new(function() end)
      mock_docsettings.flushCustomCover = spy.new(function() return true end)
      mock_docregistry.isImageFile = spy.new(function(_, f) return f:match("%.jpg$") ~= nil end)
    end)

    after_each(function()
      os.remove = original_os_remove
    end)

    it("removes custom cover if it already exists", function()
      local instance = BookInfo:new({})
      instance.custom_book_cover = "/covers/custom.jpg"
      instance.updateBookInfo = spy.new(function() end)

      instance:setCustomCover("/books/book.epub", {})

      assert.spy(os.remove).was_called_with("/covers/custom.jpg")
      assert.spy(mock_docsettings.removeSidecarDir).was_called(1)
      assert.spy(instance.updateBookInfo).was_called_with(instance, "/books/book.epub", {}, "cover")
    end)

    it("shows pathchooser to select an image if custom cover does not exist", function()
      local instance = BookInfo:new({})
      instance.custom_book_cover = nil
      instance.updateBookInfo = spy.new(function() end)

      instance:setCustomCover("/books/book.epub", {})

      assert.spy(mock_pathchooser.new).was_called(1)
      local chooser_args = mock_pathchooser.new.calls[1].refs[2]
      assert.is_false(chooser_args.select_directory)
      assert.is_function(chooser_args.file_filter)
      assert.is_function(chooser_args.onConfirm)

      -- Test file filter
      assert.is_true(chooser_args.file_filter("test.jpg"))
      assert.is_false(chooser_args.file_filter("test.txt"))

      -- Test onConfirm
      chooser_args.onConfirm("/covers/new_custom.jpg")
      assert.spy(mock_docsettings.flushCustomCover).was_called_with(mock_docsettings, "/books/book.epub", "/covers/new_custom.jpg")
      assert.spy(instance.updateBookInfo).was_called_with(instance, "/books/book.epub", {}, "cover")
      assert.spy(mock_uimanager.show).was_called_with(mock_uimanager, match.is_table()) -- shows path_chooser
    end)
  end)

  describe("setCustomCoverFromImage", function()
    local original_os_remove

    before_each(function()
      original_os_remove = os.remove
      os.remove = spy.new(function() return true end)
      mock_docsettings.flushCustomCover = spy.new(function() return true end)
      mock_docsettings.findCustomCoverFile = spy.new(function() return "/covers/custom.jpg" end)
    end)

    after_each(function()
      os.remove = original_os_remove
    end)

    it("removes existing custom cover and flushes new one", function()
      local instance = BookInfo:new({})
      instance.ui = {
        doc_settings = {
          getCustomCoverFile = spy.new(function() end)
        }
      }

      instance:setCustomCoverFromImage("/books/book.epub", "/covers/new_custom.jpg")

      assert.spy(mock_docsettings.findCustomCoverFile).was_called_with(mock_docsettings, "/books/book.epub")
      assert.spy(os.remove).was_called_with("/covers/custom.jpg")
      assert.spy(mock_docsettings.flushCustomCover).was_called_with(mock_docsettings, "/books/book.epub", "/covers/new_custom.jpg")
      assert.spy(instance.ui.doc_settings.getCustomCoverFile).was_called_with(instance.ui.doc_settings, true)
      assert.spy(mock_uimanager.broadcastEvent).was_called(2)
    end)
  end)

  describe("setCustomMetadata", function()
    local mock_settings_instance

    before_each(function()
      mock_settings_instance = {
        file = "/metadata/book.lua",
        save = spy.new(function() end),
        read = spy.new(function(_, k) if k == "doc_props" then return {} end end),
        readTableRef = spy.new(function(_, k)
          if k == "custom_props" then
            return mock_settings_instance.custom_props_data or {}
          end
          return {}
        end),
        purge = spy.new(function() end),
        flushCustomMetadata = spy.new(function() end),
      }
      mock_settings_instance.custom_props_data = {}

      mock_docsettings.openSettingsFile = spy.new(function(file)
        if file then
          mock_settings_instance.file = file
        end
        return mock_settings_instance
      end)
      mock_docsettings.removeSidecarDir = spy.new(function() end)
    end)

    it("creates a new custom metadata file if it does not exist and saves original props", function()
      local instance = BookInfo:new({})
      instance.updateBookInfo = spy.new(function() end)
      instance.custom_doc_settings = nil

      local book_props = {
        title = "Original Title",
        display_title = "display_title_backup",
      }

      instance:setCustomMetadata("/books/book.epub", book_props, "title", "New Title")

      assert.spy(mock_docsettings.openSettingsFile).was_called_with()
      assert.spy(mock_settings_instance.save).was_called_with(match.is_table(), "doc_props", { title = "Original Title" })
      assert.are.equal("New Title", book_props.title)
      assert.are.equal("New Title", book_props.display_title)
      assert.spy(mock_settings_instance.flushCustomMetadata).was_called_with(match.is_table(), "/books/book.epub")
      assert.spy(instance.updateBookInfo).was_called_with(instance, "/books/book.epub", book_props, "title", "Original Title")
    end)

    it("uses existing custom metadata and updates customized field", function()
      local instance = BookInfo:new({})
      instance.updateBookInfo = spy.new(function() end)
      instance.custom_doc_settings = mock_settings_instance
      mock_settings_instance.custom_props_data = {
        title = "Custom Title 1"
      }

      local book_props = {
        title = "Custom Title 1",
      }

      instance:setCustomMetadata("/books/book.epub", book_props, "title", "Custom Title 2")

      assert.spy(mock_settings_instance.flushCustomMetadata).was_called_with(match.is_table(), "/books/book.epub")
      assert.are.equal("Custom Title 2", book_props.title)
      assert.spy(instance.updateBookInfo).was_called_with(instance, "/books/book.epub", book_props, "title", "Custom Title 1")
    end)

    it("purges custom metadata file if no custom props remain after reset", function()
      local instance = BookInfo:new({})
      instance.updateBookInfo = spy.new(function() end)
      instance.custom_doc_settings = mock_settings_instance
      mock_settings_instance.custom_props_data = {
        title = "Custom Title"
      }

      local book_props = {
        title = "Custom Title",
      }

      instance:setCustomMetadata("/books/book.epub", book_props, "title", nil)

      assert.spy(mock_settings_instance.purge).was_called(1)
      assert.spy(mock_docsettings.removeSidecarDir).was_called_with("/metadata/", "book.lua")
      assert.spy(instance.updateBookInfo).was_called_with(instance, "/books/book.epub", book_props, "title", "Custom Title")
    end)
  end)

  describe("showCustomEditDialog", function()
    it("shows InputDialog to edit metadata and saves on Save click", function()
      local instance = BookInfo:new({})
      instance.setCustomMetadata = spy.new(function() end)

      local book_props = {
        title = "Original Title"
      }

      instance:showCustomEditDialog("/books/book.epub", book_props, "title")

      assert.spy(mock_input_dialog.new).was_called(1)
      local dialog_args = mock_input_dialog.new.calls[1].refs[2]
      assert.are.equal("Edit book metadata: Title", dialog_args.title)
      assert.are.equal("Original Title", dialog_args.input)
      assert.is_table(dialog_args.buttons)

      local save_btn = dialog_args.buttons[1][2]
      assert.are.equal("Save", save_btn.text)

      local dialog_mock = mock_uimanager.show.calls[1].refs[2]
      dialog_mock.input_text = "New Title"
      save_btn.callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, dialog_mock)
      assert.spy(instance.setCustomMetadata).was_called_with(instance, "/books/book.epub", book_props, "title", "New Title")
    end)
  end)

  describe("showCustomDialog", function()
    local original_prop, custom_prop
    local instance

    before_each(function()
      instance = BookInfo:new({})
      instance.custom_doc_settings = {
        readTableRef = spy.new(function(_, k)
          if k == "doc_props" then
            return { title = "Original Title" }
          elseif k == "custom_props" then
            return custom_prop and { title = "Custom Title" } or {}
          end
          return {}
        end)
      }
      instance.custom_book_cover = nil
      original_prop = "Original Title"
      custom_prop = false

      instance.onShowBookCover = spy.new(function() end)
      instance.showBookProp = spy.new(function() end)
      instance.setCustomCover = spy.new(function() end)
      instance.setCustomMetadata = spy.new(function() end)
      instance.showCustomEditDialog = spy.new(function() end)
    end)

    it("shows ButtonDialog for metadata and handles 'Copy original'", function()
      instance:showCustomDialog("/books/book.epub", { title = "Original Title" }, "title")

      assert.spy(mock_button_dialog.new).was_called(1)
      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      assert.are.equal("Book metadata: Title", dialog_args.title)

      local copy_btn = dialog_args.buttons[1][1]
      assert.are.equal("Copy original", copy_btn.text)
      assert.is_true(copy_btn.enabled)

      local Device = require("device")
      copy_btn.callback()
      assert.spy(Device.input.setClipboardText).was_called_with("Original Title")
    end)

    it("shows ButtonDialog for metadata and handles 'View original'", function()
      instance:showCustomDialog("/books/book.epub", { title = "Original Title" }, "title")

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      local view_btn = dialog_args.buttons[1][2]
      assert.are.equal("View original", view_btn.text)
      assert.is_true(view_btn.enabled)

      view_btn.callback()
      assert.spy(instance.showBookProp).was_called_with(instance, "title", "Original Title")
    end)

    it("shows ButtonDialog for metadata and handles 'Reset custom'", function()
      custom_prop = true
      instance:showCustomDialog("/books/book.epub", { title = "Custom Title" }, "title")

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      local reset_btn = dialog_args.buttons[2][1]
      assert.are.equal("Reset custom", reset_btn.text)
      assert.is_true(reset_btn.enabled)

      reset_btn.callback()
      assert.spy(mock_confirm_box.new).was_called(1)
      local confirm_args = mock_confirm_box.new.calls[1].refs[2]
      assert.are.equal("Reset custom book metadata field?", confirm_args.text)

      confirm_args.ok_callback()
      assert.spy(instance.setCustomMetadata).was_called_with(instance, "/books/book.epub", { title = "Custom Title" }, "title")
    end)

    it("shows ButtonDialog for metadata and handles 'Set custom'", function()
      instance:showCustomDialog("/books/book.epub", { title = "Original Title" }, "title")

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      local set_btn = dialog_args.buttons[2][2]
      assert.are.equal("Set custom", set_btn.text)
      assert.is_true(set_btn.enabled)

      set_btn.callback()
      assert.spy(instance.showCustomEditDialog).was_called_with(instance, "/books/book.epub", { title = "Original Title" }, "title")
    end)

    it("shows ButtonDialog for cover and handles 'View original' cover", function()
      instance.custom_book_cover = "/covers/custom_cover.jpg"
      instance:showCustomDialog("/books/book.epub", {})

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      assert.are.equal("Book metadata: Cover image", dialog_args.title)

      local view_btn = dialog_args.buttons[1][2]
      assert.are.equal("View original", view_btn.text)
      assert.is_true(view_btn.enabled)

      view_btn.callback()
      assert.spy(instance.onShowBookCover).was_called_with(instance, "/books/book.epub", true)
    end)

    it("shows ButtonDialog for cover and handles 'Reset custom' cover", function()
      instance.custom_book_cover = "/covers/custom_cover.jpg"
      instance:showCustomDialog("/books/book.epub", {})

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      local reset_btn = dialog_args.buttons[2][1]
      assert.are.equal("Reset custom", reset_btn.text)
      assert.is_true(reset_btn.enabled)

      reset_btn.callback()
      assert.spy(mock_confirm_box.new).was_called(1)
      local confirm_args = mock_confirm_box.new.calls[1].refs[2]
      assert.are.equal("Reset custom cover?\nImage file will be deleted.", confirm_args.text)

      confirm_args.ok_callback()
      assert.spy(instance.setCustomCover).was_called_with(instance, "/books/book.epub", {})
    end)

    it("shows ButtonDialog for cover and handles 'Set custom' cover", function()
      instance.custom_book_cover = nil
      instance:showCustomDialog("/books/book.epub", {})

      local dialog_args = mock_button_dialog.new.calls[1].refs[2]
      local set_btn = dialog_args.buttons[2][2]
      assert.are.equal("Set custom", set_btn.text)
      assert.is_true(set_btn.enabled)

      set_btn.callback()
      assert.spy(instance.setCustomCover).was_called_with(instance, "/books/book.epub", {})
    end)
  end)

  describe("editSummary", function()
    local mock_settings
    local instance

    before_each(function()
      instance = BookInfo:new({})
      instance.show = spy.new(function() end)
      instance.kvp_widget = {
        onExit = spy.new(function() end)
      }

      mock_settings = {
        readTableRef = spy.new(function(_, key)
          if key == "summary" then
            return { rating = 3, note = "Initial Note" }
          end
          return {}
        end)
      }

      local fm_util = require("apps/filemanager/filemanagerutil")
      fm_util.saveSummary = spy.new(function(settings, summary)
        return settings
      end)
    end)

    it("shows InputDialog with note and rating buttons, and saves review on rating button click", function()
      instance:editSummary(mock_settings, {})

      assert.spy(mock_input_dialog.new).was_called(1)
      local dialog_args = mock_input_dialog.new.calls[1].refs[2]
      assert.are.equal("Edit book review", dialog_args.title)
      assert.are.equal("Initial Note", dialog_args.input)

      local row = dialog_args.buttons[1]
      assert.are.equal(9, #row)
      assert.are.equal("★", row[3].text)
      assert.are.equal("★", row[4].text)
      assert.are.equal("★", row[5].text)
      assert.are.equal("☆", row[6].text)
      assert.are.equal("☆", row[7].text)

      local dialog_mock = mock_uimanager.show.calls[1].refs[2]
      dialog_mock.getInputText = function() return "New Note" end
      row[6].callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, dialog_mock)

      local fm_util = require("apps/filemanager/filemanagerutil")
      assert.spy(fm_util.saveSummary).was_called_with(mock_settings, { rating = 4, note = "New Note" })
      assert.is_true(instance.summary_updated)
      assert.spy(instance.show).was_called_with(instance, mock_settings, {})
    end)

    it("saves review on 'Save review' button click", function()
      instance:editSummary(mock_settings, {})

      local dialog_args = mock_input_dialog.new.calls[1].refs[2]
      local save_btn = dialog_args.buttons[2][2]
      assert.are.equal("Save review", save_btn.text)

      local dialog_mock = mock_uimanager.show.calls[1].refs[2]
      dialog_mock.getInputText = function() return "Another Note" end
      save_btn.callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, dialog_mock)

      local fm_util = require("apps/filemanager/filemanagerutil")
      assert.spy(fm_util.saveSummary).was_called_with(mock_settings, { rating = 3, note = "Another Note" })
      assert.is_true(instance.summary_updated)
      assert.spy(instance.show).was_called_with(instance, mock_settings, {})
    end)
  end)

  describe("moveBookMetadata", function()
    local instance
    local mock_file_chooser
    local scan_files = {}
    local dir_attributes = {}

    before_each(function()
      mock_file_chooser = {
        path = "/books",
        show_dir = spy.new(function() return true end),
        show_file = spy.new(function() return true end),
        refreshPath = spy.new(function() end),
      }
      instance = BookInfo:new({
        ui = {
          file_chooser = mock_file_chooser,
        },
        menu_container = {}
      })

      local real_lfs = require("libs/libkoreader-lfs")
      original_lfs_dir = real_lfs.dir
      real_lfs.dir = spy.new(function(path)
        local files = scan_files[path]
        if files then
          local i = 0
          return function()
            i = i + 1
            return files[i]
          end
        end
        return function() return nil end
      end)

      original_lfs_attributes = real_lfs.attributes
      real_lfs.attributes = spy.new(function(file, field)
        local attr = dir_attributes[file]
        if attr then
          if field then
            return attr[field]
          end
          return attr
        end
        return nil
      end)

      mock_docsettings.isSidecarFileNotInPreferredLocation = spy.new(function(path)
        return path == "/books/file1.epub"
      end)
      mock_docsettings.updateLocation = spy.new(function() end)
    end)

    after_each(function()
      local real_lfs = require("libs/libkoreader-lfs")
      real_lfs.dir = original_lfs_dir
      real_lfs.attributes = original_lfs_attributes
    end)

    it("scans path and alerts if no books with legacy metadata are found", function()
      scan_files["/books"] = { ".", "..", "file2.epub" }
      dir_attributes["/books/file2.epub"] = { mode = "file" }

      instance:moveBookMetadata()

      assert.spy(mock_confirm_box.new).was_called(1)
      local scan_confirm = mock_confirm_box.new.calls[1].refs[2]
      assert.are.equal("Scan books in current folder and subfolders for their metadata location?", scan_confirm.text)

      scan_confirm.ok_callback()

      assert.spy(mock_info_message.new).was_called(1)
      local info_dialog = mock_info_message.new.calls[1].refs[2]
      assert.are.equal("No books with metadata not in your preferred location found.", info_dialog.text)
    end)

    it("scans path, finds legacy books, and moves metadata on confirmation", function()
      scan_files["/books"] = { ".", "..", "file1.epub", "subdir" }
      scan_files["/books/subdir"] = { ".", "..", "file3.epub" }

      dir_attributes["/books/file1.epub"] = { mode = "file" }
      dir_attributes["/books/subdir"] = { mode = "directory" }
      dir_attributes["/books/subdir/file3.epub"] = { mode = "file" }

      mock_docsettings.isSidecarFileNotInPreferredLocation = spy.new(function(path)
        return path == "/books/file1.epub" or path == "/books/subdir/file3.epub"
      end)

      instance:moveBookMetadata()

      local scan_confirm = mock_confirm_box.new.calls[1].refs[2]
      scan_confirm.ok_callback()

      assert.spy(mock_confirm_box.new).was_called(2)
      local move_confirm = mock_confirm_box.new.calls[2].refs[2]
      assert.match("2 books with metadata not in your preferred location found.", move_confirm.text)

      move_confirm.ok_callback()

      assert.spy(mock_uimanager.close).was_called_with(mock_uimanager, instance.menu_container)
      assert.spy(mock_docsettings.updateLocation).was_called(2)
      assert.spy(mock_docsettings.updateLocation).was_called_with("/books/file1.epub", "/books/file1.epub")
      assert.spy(mock_docsettings.updateLocation).was_called_with("/books/subdir/file3.epub", "/books/subdir/file3.epub")
      assert.spy(mock_file_chooser.refreshPath).was_called(1)
    end)
  end)

  describe("showBooksWithHashBasedMetadata", function()
    local original_lfs_attributes

    before_each(function()
      mock_docsettings.getSidecarStorage = spy.new(function(type) return "/hash_path" end)
      mock_docsettings.findSidecarFilesInHashLocation = spy.new(function()
        return {
          { "/hash_path/book1_sidecar.lua", "/hash_path/book1_custom.lua" },
          { "/hash_path/book2_sidecar.lua", nil }
        }
      end)

      mock_docsettings.openSettingsFile = spy.new(function(file)
        if file == "/hash_path/book1_sidecar.lua" then
          return {
            read = function(_, key)
              if key == "doc_props" then return { title = "Orig Title 1", authors = "Author 1" }
              elseif key == "doc_path" then return "/books/book1.epub" end
            end
          }
        elseif file == "/hash_path/book1_custom.lua" then
          return {
            readTableRef = function(_, key)
              if key == "custom_props" then return { title = "Custom Title 1" } end
              return {}
            end
          }
        elseif file == "/hash_path/book2_sidecar.lua" then
          return {
            read = function(_, key)
              if key == "doc_props" then return { title = "Orig Title 2", authors = "Author 2" }
              elseif key == "doc_path" then return "/books/book2.epub" end
            end
          }
        end
        return { read = function() end, readTableRef = function() return {} end }
      end)

      local real_lfs = require("libs/libkoreader-lfs")
      original_lfs_attributes = real_lfs.attributes
      real_lfs.attributes = spy.new(function(path, field)
        if field == "mode" then
          if path == "/books/book1.epub" then return "file" end
          if path == "/books/book2.epub" then return nil end
        end
        return nil
      end)
    end)

    after_each(function()
      local real_lfs = require("libs/libkoreader-lfs")
      real_lfs.attributes = original_lfs_attributes
    end)

    it("collects hash-based metadata, resolves paths, and displays TextViewer with results", function()
      BookInfo.showBooksWithHashBasedMetadata()

      assert.spy(mock_text_viewer.new).was_called(1)
      local viewer_args = mock_text_viewer.new.calls[1].refs[2]
      assert.are.equal("2 documents with hash-based metadata", viewer_args.title)
      assert.is_true(viewer_args.title_multilines)

      assert.truthy(viewer_args.text:find("1. Title: Custom Title 1; Author: Author 1\nDocument: /books/book1.epub", 1, true))
      assert.truthy(viewer_args.text:find("2. Title: Orig Title 2; Author: Author 2\nDocument: N/A", 1, true))
    end)
  end)
end)
