describe("Calibre Search module", function()
  local CalibreSearch, CalibreMetadata, UIManager, Device, G_reader_settings
  local lfs, Persist, DataStorage, rapidjson, ReaderUI

  local sample_books

  local function contains(tbl, value)
    if not tbl then
      return false
    end
    for _, v in ipairs(tbl) do
      if v == value then
        return true
      end
    end
    return false
  end

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    CalibreSearch = require("plugins/calibre.koplugin/search")
    CalibreMetadata = require("plugins/calibre.koplugin/metadata")
    UIManager = require("ui/uimanager")
    Device = require("device")
    lfs = require("libs/libkoreader-lfs")
    Persist = require("persist")
    DataStorage = require("datastorage")
    rapidjson = require("rapidjson")
    ReaderUI = require("apps/reader/readerui")
  end)

  before_each(function()
    sample_books = {
      {
        title = "Dune",
        authors = { "Frank Herbert" },
        series = "Dune Chronicles",
        series_index = 1,
        tags = { "Sci-Fi", "Classic" },
        lpath = "Frank Herbert/Dune.epub",
        rootpath = "/mnt/calibre",
        size = 1048576,
      },
      {
        title = "Dune Messiah",
        authors = { "Frank Herbert" },
        series = "Dune Chronicles",
        series_index = 2.5,
        tags = { "Sci-Fi" },
        lpath = "Frank Herbert/Dune Messiah.epub",
        rootpath = "/mnt/calibre",
        size = 2097152,
      },
      {
        title = "Foundation",
        authors = { "Isaac Asimov" },
        series = "Foundation Series",
        series_index = 1,
        tags = { "Sci-Fi", "Space Opera" },
        lpath = "Isaac Asimov/Foundation.epub",
        rootpath = "/mnt/calibre",
        size = 524288,
      },
      {
        title = "The Hobbit",
        authors = { "J.R.R. Tolkien" },
        series = nil,
        series_index = nil,
        tags = { "Fantasy" },
        lpath = "Tolkien/The Hobbit.epub",
        rootpath = "/mnt/calibre",
        size = 1572864,
      },
    }

    CalibreSearch.books = {}
    CalibreSearch.libraries = {}
    CalibreSearch.natsort_cache = {}
    CalibreSearch.last_scan = {}
    CalibreSearch.search_value = nil
    CalibreSearch.lastsearch = nil
    CalibreSearch.search_menu = nil
    CalibreSearch.search_dialog = nil
  end)

  describe("Module initialization", function()
    it("should export CalibreSearch singleton table", function()
      assert.is_table(CalibreSearch)
      assert.is_table(CalibreSearch.default_search_options)
      assert.is_table(CalibreSearch.extra_search_options)
    end)

    it("should contain default and extra search option flags", function()
      assert.is_true(
        contains(CalibreSearch.default_search_options, "cache_metadata")
      )
      assert.is_true(
        contains(CalibreSearch.default_search_options, "case_insensitive")
      )
      assert.is_true(
        contains(CalibreSearch.default_search_options, "find_by_title")
      )
      assert.is_true(
        contains(CalibreSearch.default_search_options, "find_by_authors")
      )
      assert.is_true(
        contains(CalibreSearch.extra_search_options, "find_by_series")
      )
      assert.is_true(
        contains(CalibreSearch.extra_search_options, "find_by_tag")
      )
      assert.is_true(
        contains(CalibreSearch.extra_search_options, "find_by_path")
      )
    end)
  end)

  describe("findBooks query matching", function()
    before_each(function()
      CalibreSearch.books = sample_books
      CalibreSearch.case_insensitive = true
      CalibreSearch.find_by_title = false
      CalibreSearch.find_by_authors = false
      CalibreSearch.find_by_series = false
      CalibreSearch.find_by_tag = false
      CalibreSearch.find_by_path = false
    end)

    it("should find books by title (case-insensitive)", function()
      CalibreSearch.find_by_title = true
      CalibreSearch.case_insensitive = true
      local results = CalibreSearch:findBooks("dune")
      assert.are.same(#results, 2)
      assert.are.same(results[1].title, "Dune")
      assert.are.same(results[2].title, "Dune Messiah")
    end)

    it("should respect case-sensitivity when disabled", function()
      CalibreSearch.find_by_title = true
      CalibreSearch.case_insensitive = false
      local results_lower = CalibreSearch:findBooks("dune")
      assert.are.same(#results_lower, 0)

      local results_exact = CalibreSearch:findBooks("Dune")
      assert.are.same(#results_exact, 2)
    end)

    it("should find books by authors", function()
      CalibreSearch.find_by_authors = true
      local results = CalibreSearch:findBooks("Asimov")
      assert.are.same(#results, 1)
      assert.are.same(results[1].title, "Foundation")
    end)

    it("should find books by series", function()
      CalibreSearch.find_by_series = true
      local results = CalibreSearch:findBooks("Foundation Series")
      assert.are.same(#results, 1)
      assert.are.same(results[1].title, "Foundation")
    end)

    it("should find books by tag", function()
      CalibreSearch.find_by_tag = true
      local results = CalibreSearch:findBooks("Fantasy")
      assert.are.same(#results, 1)
      assert.are.same(results[1].title, "The Hobbit")
    end)

    it("should find books by path", function()
      CalibreSearch.find_by_path = true
      local results = CalibreSearch:findBooks("Tolkien")
      assert.are.same(#results, 1)
      assert.are.same(results[1].title, "The Hobbit")
    end)

    it("should return empty table when query does not match", function()
      CalibreSearch.find_by_title = true
      CalibreSearch.find_by_authors = true
      local results = CalibreSearch:findBooks("NonexistentBookQuery")
      assert.are.same(#results, 0)
    end)
  end)

  describe("bookCatalog entry formatting", function()
    it("should build basic catalog entries without series", function()
      local catalog = CalibreSearch:bookCatalog({ sample_books[4] })
      assert.are.same(#catalog, 1)
      assert.are.same(catalog[1].text, "The Hobbit - J.R.R. Tolkien")
      assert.are.same(
        catalog[1].path,
        "/mnt/calibre/Tolkien/The Hobbit.epub"
      )
      assert.is_string(catalog[1].info)
      assert.is_not_nil(string.find(catalog[1].info, "The Hobbit"))
      assert.is_not_nil(string.find(catalog[1].info, "J.R.R. Tolkien"))
      assert.is_not_nil(string.find(catalog[1].info, "Fantasy"))
    end)

    it(
      "should format series index without subseries (.00 stripped)",
      function()
        local catalog =
          CalibreSearch:bookCatalog({ sample_books[1] }, "series")
        assert.are.same(#catalog, 1)
        assert.are.same(catalog[1].text, "0000 | Dune - Frank Herbert")
      end
    )

    it("should retain subseries index when non-zero decimal", function()
      local catalog = CalibreSearch:bookCatalog({ sample_books[2] }, "series")
      assert.are.same(#catalog, 1)
      assert.are.same(catalog[1].text, "00002.50 | Dune Messiah - Frank Herbert")
    end)

    it(
      "should execute callback to open reader when entry selected",
      function()
        local catalog = CalibreSearch:bookCatalog({ sample_books[1] })
        stub(UIManager, "broadcastEvent")
        stub(ReaderUI, "showReader")

        CalibreSearch.search_menu = {
          onExit = function() end,
        }

        catalog[1].callback()

        assert.stub(UIManager.broadcastEvent).was_called(1)
        assert.stub(ReaderUI.showReader).was_called_with(
          "/mnt/calibre/Frank Herbert/Dune.epub"
        )

        UIManager.broadcastEvent:revert()
        ReaderUI.showReader:revert()
      end
    )
  end)

  describe("browse and search criteria", function()
    before_each(function()
      CalibreSearch.books = sample_books
      CalibreSearch.case_insensitive = true
      stub(UIManager, "show")
    end)

    after_each(function()
      UIManager.show:revert()
    end)

    it("should browse by tags and count occurrences", function()
      CalibreSearch.search_value = ""
      CalibreSearch:browse("tags")

      assert.is_not_nil(CalibreSearch.search_menu)
      assert.is_table(CalibreSearch.search_menu.item_table)

      local item_texts = {}
      for _, item in ipairs(CalibreSearch.search_menu.item_table) do
        table.insert(item_texts, item.text)
      end
      assert.is_true(contains(item_texts, "Sci-Fi (3)"))
      assert.is_true(contains(item_texts, "Fantasy (1)"))
      assert.is_true(contains(item_texts, "Classic (1)"))
    end)

    it("should browse by series and count occurrences", function()
      CalibreSearch.search_value = ""
      CalibreSearch:browse("series")

      local item_texts = {}
      for _, item in ipairs(CalibreSearch.search_menu.item_table) do
        table.insert(item_texts, item.text)
      end
      assert.is_true(contains(item_texts, "Dune Chronicles (2)"))
      assert.is_true(contains(item_texts, "Foundation Series (1)"))
    end)

    it("should browse by authors and count occurrences", function()
      CalibreSearch.search_value = ""
      CalibreSearch:browse("authors")

      local item_texts = {}
      for _, item in ipairs(CalibreSearch.search_menu.item_table) do
        table.insert(item_texts, item.text)
      end
      assert.is_true(contains(item_texts, "Frank Herbert (2)"))
      assert.is_true(contains(item_texts, "Isaac Asimov (1)"))
    end)

    it("should browse by titles and count occurrences", function()
      CalibreSearch.search_value = ""
      CalibreSearch:browse("title")

      local item_texts = {}
      for _, item in ipairs(CalibreSearch.search_menu.item_table) do
        table.insert(item_texts, item.text)
      end
      assert.is_true(contains(item_texts, "Dune (1)"))
      assert.is_true(contains(item_texts, "Foundation (1)"))
    end)

    it("should browse find books directly when option is find", function()
      CalibreSearch.search_value = "Dune"
      CalibreSearch.find_by_title = true
      CalibreSearch:browse("find")

      assert.is_not_nil(CalibreSearch.search_menu)
      assert.are.same(#CalibreSearch.search_menu.item_table, 2)
    end)

    it("should handle return action from nested browse levels", function()
      CalibreSearch.search_value = ""
      CalibreSearch:browse("tags")

      assert.is_function(CalibreSearch.search_menu.onReturn)
      CalibreSearch.search_menu.paths = { { page = 1 } }
      CalibreSearch.search_menu.onReturn()
      assert.are.same(#CalibreSearch.search_menu.paths, 0)
    end)
  end)

  describe("expandSearchResults and switchResults", function()
    before_each(function()
      CalibreSearch.books = sample_books
      stub(UIManager, "show")
      CalibreSearch:browse("tags")
    end)

    after_each(function()
      UIManager.show:revert()
    end)

    it(
      "should expand nested tag search results into catalog items",
      function()
        CalibreSearch:expandSearchResults("tags", "Sci-Fi")
        assert.is_not_nil(CalibreSearch.search_menu)
        assert.are.same(#CalibreSearch.search_menu.item_table, 3)
      end
    )

    it(
      "should expand field series search results into catalog items",
      function()
        CalibreSearch:expandSearchResults("series", "Foundation Series")
        assert.is_not_nil(CalibreSearch.search_menu)
        assert.are.same(#CalibreSearch.search_menu.item_table, 1)
        assert.are.same(
          CalibreSearch.search_menu.item_table[1].text,
          "0000 | Foundation - Isaac Asimov"
        )
      end
    )

    it("should sort items naturally in switchResults", function()
      local items = {
        { text = "Book 10" },
        { text = "Book 2" },
        { text = "Book 1" },
      }
      CalibreSearch:switchResults(items, "Test Title", false)
      assert.are.same(CalibreSearch.search_menu.item_table[1].text, "Book 1")
      assert.are.same(CalibreSearch.search_menu.item_table[2].text, "Book 2")
      assert.are.same(CalibreSearch.search_menu.item_table[3].text, "Book 10")
    end)

    it("should record path page history when is_child is true", function()
      CalibreSearch.search_menu.paths = {}
      local items = { { text = "Book A" } }
      CalibreSearch:switchResults(items, "Child Title", true)
      assert.are.same(#CalibreSearch.search_menu.paths, 1)
    end)
  end)

  describe("scan and findCalibre directory discovery", function()
    local test_dir = "/tmp/calibre_unit_test_" .. os.time()

    before_each(function()
      lfs.mkdir(test_dir)
      lfs.mkdir(test_dir .. "/lib_a")
      lfs.mkdir(test_dir .. "/lib_b")
      lfs.mkdir(test_dir .. "/other")

      local f1 = io.open(test_dir .. "/lib_a/metadata.calibre", "w")
      if f1 then
        f1:write("test")
        f1:close()
      end

      local f2 = io.open(test_dir .. "/lib_b/.metadata.calibre", "w")
      if f2 then
        f2:write("test")
        f2:close()
      end
    end)

    after_each(function()
      os.remove(test_dir .. "/lib_a/metadata.calibre")
      os.remove(test_dir .. "/lib_b/.metadata.calibre")
      lfs.rmdir(test_dir .. "/lib_a")
      lfs.rmdir(test_dir .. "/lib_b")
      lfs.rmdir(test_dir .. "/other")
      lfs.rmdir(test_dir)
    end)

    it("should discover libraries containing metadata files", function()
      CalibreSearch.libraries = {}
      local count, paths = CalibreSearch:scan(test_dir)

      assert.are.same(count, 2)
      assert.is_true(CalibreSearch.libraries[test_dir .. "/lib_a"])
      assert.is_true(CalibreSearch.libraries[test_dir .. "/lib_b"])
      assert.is_nil(CalibreSearch.libraries[test_dir .. "/other"])
      assert.is_string(paths)
    end)
  end)

  describe("cache invalidation and metadata retrieval", function()
    it("should invalidate books and natsort cache", function()
      CalibreSearch.books = sample_books
      CalibreSearch.natsort_cache = { key = "val" }
      stub(CalibreSearch.cache_books, "delete")

      CalibreSearch:invalidateCache()

      assert.are.same(#CalibreSearch.books, 0)
      assert.are.same(CalibreSearch.natsort_cache, {})
      assert.stub(CalibreSearch.cache_books.delete).was_called(1)

      CalibreSearch.cache_books.delete:revert()
    end)

    it("should load metadata from calibre files when cache fails", function()
      CalibreSearch.cache_metadata = false
      CalibreSearch.libraries = { ["/path/lib"] = true }

      stub(CalibreMetadata, "init").returns(true)
      stub(CalibreMetadata, "clean")
      CalibreMetadata.books = { sample_books[1] }

      local books = CalibreSearch:getMetadata()

      assert.are.same(#books, 1)
      assert.are.same(books[1].title, "Dune")
      assert.are.same(books[1].rootpath, "/path/lib")

      CalibreMetadata.init:revert()
      CalibreMetadata.clean:revert()
    end)
  end)

  describe("UI dialogs and interactions", function()
    it("should display search dialog in ShowSearch", function()
      stub(UIManager, "show")
      CalibreSearch:ShowSearch()

      assert.is_not_nil(CalibreSearch.search_dialog)
      assert.stub(UIManager.show).was_called_with(
        UIManager,
        CalibreSearch.search_dialog
      )

      UIManager.show:revert()
    end)

    it("should close search dialog and trigger search in close", function()
      stub(UIManager, "close")
      stub(CalibreSearch, "find")

      CalibreSearch.search_dialog = {
        onExit = function() end,
      }
      CalibreSearch.search_value = "Dune"
      CalibreSearch.lastsearch = "find"

      CalibreSearch:close()

      assert.stub(UIManager.close).was_called_with(
        UIManager,
        CalibreSearch.search_dialog
      )
      assert.stub(CalibreSearch.find).was_called_with(CalibreSearch, "find")

      UIManager.close:revert()
      CalibreSearch.find:revert()
    end)

    it("should display book info message onMenuHold", function()
      stub(UIManager, "show")
      local item = {
        info = "Title: Dune\nAuthor(s): Frank Herbert",
        path = "/mnt/calibre/Dune.epub",
      }

      CalibreSearch:onMenuHold(item)

      assert.stub(UIManager.show).was_called(1)

      UIManager.show:revert()
    end)
  end)
end)
