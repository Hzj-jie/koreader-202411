describe("FileChooser module", function()
  local FileChooser, DocSettings, Screen, Geom, lfs, ffiUtil, ReadCollection, FileManagerShortcuts, filemanagerutil, UIManager

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    FileChooser = require("ui/widget/filechooser")
    DocSettings = require("docsettings")
    Screen = require("device").screen
    Geom = require("ui/geometry")
    lfs = require("libs/libkoreader-lfs")
    ffiUtil = require("ffi/util")
    ReadCollection = require("readcollection")
    FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
    filemanagerutil = require("apps/filemanager/filemanagerutil")
    UIManager = require("ui/uimanager")
  end)

  it("should test all collate algorithms and mandatory text functions", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    -- 1. strcoll
    local sort_str, cache = fc.collates.strcoll.init_sort_func()
    assert.is_true(sort_str({ text = "a" }, { text = "b" }))

    -- 2. natural
    local sort_nat = fc.collates.natural.init_sort_func()
    assert.is_true(sort_nat({ text = "file2.txt" }, { text = "file10.txt" }))

    -- 3. access
    local access_item_unopened = {
      text = "f.txt",
      path = "/tmp/f.txt",
      opened = false,
      attr = { mode = "file", access = 1000, modification = 2000 },
    }
    fc.collates.access.item_func(access_item_unopened)
    assert.are_equal(2000, access_item_unopened.attr.last_read)

    local access_item_opened = {
      text = "f2.txt",
      path = "/tmp/f2.txt",
      opened = true,
      attr = { mode = "file", access = 1000, modification = 2000 },
    }
    fc.collates.access.item_func(access_item_opened)
    assert.are_equal(2000, access_item_opened.attr.last_read)

    local access_item_dir = {
      text = "dir",
      path = "/tmp/dir",
      attr = { mode = "directory", access = 5000 },
    }
    fc.collates.access.item_func(access_item_dir)
    assert.are_equal(5000, access_item_dir.attr.last_read)

    local sort_access = fc.collates.access.init_sort_func()
    assert.is_true(sort_access({ attr = { last_read = 3000 } }, { attr = { last_read = 1000 } }))
    assert.is_string(fc.collates.access.mandatory_func({ attr = { last_read = 86400 } }))
    assert.is_string(fc.collates.access.mandatory_func({ attr = { last_read = 86450 } }))

    -- 4. date
    local sort_date = fc.collates.date.init_sort_func()
    assert.is_true(sort_date({ attr = { modification = 3000 } }, { attr = { modification = 1000 } }))
    assert.is_string(fc.collates.date.mandatory_func({ attr = { modification = 1000 } }))

    -- 5. size
    local sort_size = fc.collates.size.init_sort_func()
    assert.is_true(sort_size({ attr = { size = 100 } }, { attr = { size = 200 } }))

    -- 6. type
    local type_item1 = { text = "doc.pdf", path = "/tmp/doc.pdf", attr = {} }
    local type_item2 = { text = "doc.epub", path = "/tmp/doc.epub", attr = {} }
    fc.collates.type.item_func(type_item1)
    fc.collates.type.item_func(type_item2)
    local sort_type = fc.collates.type.init_sort_func()
    assert.is_true(sort_type(type_item2, type_item1))
    assert.is_true(sort_type({ text = "a.pdf", suffix = "pdf" }, { text = "b.pdf", suffix = "pdf" }))

    -- 7. percent_unopened_first & percent_unopened_last
    local sort_unopened_first = fc.collates.percent_unopened_first.init_sort_func()
    assert.is_true(sort_unopened_first({ opened = false, text = "a" }, { opened = true, text = "b" }))
    assert.is_true(sort_unopened_first({ opened = true, percent_finished = 0.2 }, { opened = true, percent_finished = 0.8 }))
    assert.is_true(sort_unopened_first({ opened = false, text = "a" }, { opened = false, text = "b" }))

    local sort_unopened_last = fc.collates.percent_unopened_last.init_sort_func()
    assert.is_true(sort_unopened_last({ opened = true, text = "a" }, { opened = false, text = "b" }))
    assert.is_true(sort_unopened_last({ opened = true, percent_finished = 0.2 }, { opened = true, percent_finished = 0.8 }))

    assert.are_equal("–", fc.collates.percent_unopened_first.mandatory_func({ opened = false }))
    assert.are_equal("50 %", fc.collates.percent_unopened_first.mandatory_func({ opened = true, percent_finished = 0.5 }))

    -- 8. percent_natural
    local sort_pnat = fc.collates.percent_natural.init_sort_func()
    assert.is_true(sort_pnat({ sort_percent = 0.8, text = "a" }, { sort_percent = 0.5, text = "b" }))
    assert.is_false(sort_pnat({ sort_percent = 1, text = "a" }, { sort_percent = 0.5, text = "b" }))
    assert.is_true(sort_pnat({ sort_percent = 0.5, text = "a" }, { sort_percent = 1, text = "b" }))
    assert.is_true(sort_pnat({ sort_percent = 0.5, text = "a" }, { sort_percent = 0.5, text = "b" }))
  end)

  it("should test show_dir and show_file filtering rules", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    -- Excluded directory patterns
    assert.is_false(fc:show_dir("book.sdr"))
    assert.is_false(fc:show_dir(".adobe-digital-editions"))
    assert.is_false(fc:show_dir("certificates"))
    assert.is_false(fc:show_dir(".Trash"))
    assert.is_false(fc:show_dir("RECYCLED"))
    assert.is_false(fc:show_dir("System Volume Information"))
    assert.is_true(fc:show_dir("NormalFolder"))

    -- Excluded file patterns
    assert.is_false(fc:show_file("BookReader.sqlite"))
    assert.is_false(fc:show_file(".DS_Store"))
    assert.is_false(fc:show_file("Thumbs.db"))
    assert.is_false(fc:show_file("metadata.calibre"))
    assert.is_true(fc:show_file("document.epub"))

    -- file_filter function
    fc.show_unsupported = false
    fc.file_filter = function(filename) return filename:match("%.epub$") ~= nil end
    assert.is_true(fc:show_file("test.epub"))
    assert.is_false(fc:show_file("test.pdf"))
    fc.file_filter = nil
  end)

  it("should test showFileInBold options", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    local orig_show_bold = G_named_settings.show_file_in_bold
    G_named_settings.show_file_in_bold = function() return "new" end
    assert.is_true(fc:showFileInBold(false))
    assert.is_false(fc:showFileInBold(true))

    G_named_settings.show_file_in_bold = function() return "opened" end
    assert.is_true(fc:showFileInBold(true))
    assert.is_false(fc:showFileInBold(false))

    G_named_settings.show_file_in_bold = function() return "none" end
    assert.is_false(fc:showFileInBold(true))
    assert.is_false(fc:showFileInBold(false))

    G_named_settings.show_file_in_bold = orig_show_bold
  end)

  it("should get collate, sorting functions and clear sorting cache", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    local orig_collate = G_named_settings.collate
    G_named_settings.collate = function() return "natural" end
    local col, id = fc:getCollate()
    assert.are_equal("natural", id)

    G_named_settings.collate = function() return "invalid_collate_id" end
    col, id = fc:getCollate()
    assert.are_equal("strcoll", id)
    G_named_settings.collate = orig_collate

    -- Reverse collation
    local sort_fn = fc:getSortingFunction(fc.collates.strcoll, true)
    assert.is_false(sort_fn({ text = "a" }, { text = "b" }))

    -- Static class getSortingFunction
    local static_sort = FileChooser.getSortingFunction(FileChooser, fc.collates.strcoll, false)
    assert.is_true(static_sort({ text = "a" }, { text = "b" }))

    fc.sort_cache = {}
    fc:clearSortingCache()
    assert.is_nil(fc.sort_cache)
  end)

  it("should generate item tables with parent navigation and collection / shortcut stars", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp/testdir",
      show_current_dir_for_hold = true,
    })

    local dirs = {
      { text = "subfolder/", path = "/tmp/testdir/subfolder", attr = { mode = "directory" } },
    }
    local files = {
      { text = "book.epub", path = "/tmp/testdir/book.epub", is_file = true, attr = { mode = "file", size = 1024 } },
    }

    local items = fc:genItemTable(dirs, files, "/tmp/testdir")
    assert.is_table(items)
    -- Verify "Long-press to choose current folder" and "⬆ ../" were added
    assert.are_equal("Long-press to choose current folder", items[1].text)
    assert.is_true(items[2].is_go_up)

    -- Mandatory markers
    local orig_hasShortcut = FileManagerShortcuts.hasFolderShortcut
    local orig_inCol = ReadCollection.isFileInCollections
    FileManagerShortcuts.hasFolderShortcut = function() return true end
    ReadCollection.isFileInCollections = function() return true end

    fc.getList = function() return {}, {} end
    local file_mandatory = fc:getMenuItemMandatory(files[1], fc.collates.size)
    assert.is_true(file_mandatory:find("☆") ~= nil)

    local folder_mandatory = fc:getMenuItemMandatory(dirs[1])
    assert.is_true(folder_mandatory:find("☆") ~= nil)

    FileManagerShortcuts.hasFolderShortcut = orig_hasShortcut
    ReadCollection.isFileInCollections = orig_inCol
  end)

  it("should handle navigation: changeToPath, goHome, onFolderUp, and toggleShowFilesMode", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    -- changeToPath with focused_path
    fc:changeToPath("/tmp", "/tmp/focused_sub")
    assert.are_equal("/tmp", fc.path)
    assert.are_equal("/tmp/focused_sub", fc.prev_focused_path)

    -- goHome
    local home = G_named_settings.home_dir()
    assert.is_true(fc:goHome())
    assert.are_equal(home, fc.path)
    -- goHome again when already home
    assert.is_true(fc:goHome())

    -- onFolderUp
    fc:onFolderUp()

    -- toggleShowFilesMode
    local initial_hidden = FileChooser.show_hidden
    fc:toggleShowFilesMode("show_hidden")
    assert.are_equal(not initial_hidden, FileChooser.show_hidden)
    fc:toggleShowFilesMode("show_hidden")
  end)

  it("should handle menu selection, hold, and selectAllFilesInFolder", function()
    local closed = false
    local orig_close = UIManager.close
    UIManager.close = function(_, w) closed = true end

    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
      filemanager = { selected_files = {} },
    })

    -- onMenuSelect for file
    assert.is_true(fc:onMenuSelect({ is_file = true, path = "/tmp/a.epub" }))
    assert.is_true(closed)

    -- onMenuSelect for folder
    assert.is_true(fc:onMenuSelect({ is_file = false, path = "/tmp/sub", is_go_up = true }))

    -- onMenuHold
    assert.is_true(fc:onMenuHold({ is_file = true, path = "/tmp/a.epub" }))

    -- selectAllFilesInFolder
    fc.item_table = {
      { is_file = true, path = "/tmp/1.epub" },
      { is_file = true, path = "/tmp/2.epub" },
      { is_file = false, path = "/tmp/sub" },
    }
    fc:selectAllFilesInFolder(true)
    assert.is_true(fc.filemanager.selected_files["/tmp/1.epub"])
    assert.is_true(fc.filemanager.selected_files["/tmp/2.epub"])

    fc:selectAllFilesInFolder(false)
    assert.is_nil(fc.item_table[1].dim)

    UIManager.close = orig_close
  end)

  it("should handle getNextFile in folder", function()
    local fc = FileChooser:new({
      dimen = Screen:getSize(),
      path = "/tmp",
    })

    fc.genItemTableFromPath = function(self, path)
      return {
        { is_file = true, path = "/tmp/book1.epub" },
        { is_file = true, path = "/tmp/book2.epub" },
      }
    end

    local orig_hasProvider = require("document/documentregistry").hasProvider
    require("document/documentregistry").hasProvider = function() return true end

    local next_f = fc:getNextFile("/tmp/book1.epub")
    assert.are_equal("/tmp/book2.epub", next_f)

    require("document/documentregistry").hasProvider = orig_hasProvider
  end)
end)
