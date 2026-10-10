describe("Calibre Search module", function()
  local Search
  local UIManager

  setup(function()
    require("commonrequire")
    Search = require("plugins/calibre.koplugin/search")
    UIManager = require("ui/uimanager")
  end)

  describe("module initialization and options", function()
    it("should initialize Calibre Search module and default fields", function()
      assert.is_table(Search)
      assert.is_table(Search.default_search_options)
      assert.is_table(Search.extra_search_options)
      assert.is_truthy(Search.cache_dir:find("cache/calibre"))
      assert.is_table(Search.cache_libs)
      assert.is_table(Search.cache_books)
    end)
  end)

  describe("findBooks", function()
    local saved_books
    local saved_opts = {}

    before_each(function()
      saved_books = Search.books
      saved_opts = {
        case_insensitive = Search.case_insensitive,
        find_by_title = Search.find_by_title,
        find_by_authors = Search.find_by_authors,
        find_by_series = Search.find_by_series,
        find_by_tag = Search.find_by_tag,
        find_by_path = Search.find_by_path,
      }

      Search.books = {
        {
          title = "The Hobbit",
          authors = { "J.R.R. Tolkien" },
          series = "Middle-earth",
          tags = { "Fantasy", "Classic" },
          lpath = "tolkien/hobbit.epub",
          rootpath = "/library",
          size = 1048576,
        },
        {
          title = "Dune",
          authors = { "Frank Herbert" },
          series = "Dune Chronicles",
          tags = { "Sci-Fi" },
          lpath = "herbert/dune.epub",
          rootpath = "/library",
          size = 2097152,
        },
        {
          title = "Foundation",
          authors = { "Isaac Asimov" },
          series = "Foundation",
          tags = { "Sci-Fi", "Classic" },
          lpath = "asimov/foundation.epub",
          rootpath = "/library",
          size = 524288,
        },
      }
    end)

    after_each(function()
      Search.books = saved_books
      for k, v in pairs(saved_opts) do
        Search[k] = v
      end
    end)

    it("matches books by title case-insensitively", function()
      Search.case_insensitive = true
      Search.find_by_title = true
      Search.find_by_authors = false
      Search.find_by_series = false
      Search.find_by_tag = false
      Search.find_by_path = false

      local results = Search:findBooks("hobbit")
      assert.are.equal(1, #results)
      assert.are.equal("The Hobbit", results[1].title)
    end)

    it("matches books by title case-sensitively", function()
      Search.case_insensitive = false
      Search.find_by_title = true
      Search.find_by_authors = false
      Search.find_by_series = false
      Search.find_by_tag = false
      Search.find_by_path = false

      local results = Search:findBooks("hobbit")
      assert.are.equal(0, #results)

      results = Search:findBooks("Hobbit")
      assert.are.equal(1, #results)
      assert.are.equal("The Hobbit", results[1].title)
    end)

    it("matches books by authors", function()
      Search.case_insensitive = true
      Search.find_by_title = false
      Search.find_by_authors = true
      Search.find_by_series = false
      Search.find_by_tag = false
      Search.find_by_path = false

      local results = Search:findBooks("Herbert")
      assert.are.equal(1, #results)
      assert.are.equal("Dune", results[1].title)
    end)

    it("matches books by series", function()
      Search.case_insensitive = true
      Search.find_by_title = false
      Search.find_by_authors = false
      Search.find_by_series = true
      Search.find_by_tag = false
      Search.find_by_path = false

      local results = Search:findBooks("Middle")
      assert.are.equal(1, #results)
      assert.are.equal("The Hobbit", results[1].title)
    end)

    it("matches books by tags", function()
      Search.case_insensitive = true
      Search.find_by_title = false
      Search.find_by_authors = false
      Search.find_by_series = false
      Search.find_by_tag = true
      Search.find_by_path = false

      local results = Search:findBooks("Classic")
      assert.are.equal(2, #results)
    end)

    it("matches books by path", function()
      Search.case_insensitive = true
      Search.find_by_title = false
      Search.find_by_authors = false
      Search.find_by_series = false
      Search.find_by_tag = false
      Search.find_by_path = true

      local results = Search:findBooks("asimov/foundation")
      assert.are.equal(1, #results)
      assert.are.equal("Foundation", results[1].title)
    end)

    it(
      "returns empty results for non-matching queries or nil queries",
      function()
        Search.case_insensitive = true
        Search.find_by_title = true
        Search.find_by_authors = true
        Search.find_by_series = true
        Search.find_by_tag = true
        Search.find_by_path = true

        local results = Search:findBooks("NonExistentString12345")
        assert.are.equal(0, #results)

        results = Search:findBooks(nil)
        assert.are.equal(0, #results)
      end
    )

    it("gracefully handles books with nil attributes", function()
      table.insert(Search.books, {
        title = nil,
        authors = {},
        series = nil,
        tags = {},
        lpath = nil,
      })
      Search.find_by_title = true
      Search.find_by_authors = true
      Search.find_by_series = true
      Search.find_by_tag = true
      Search.find_by_path = true

      local results = Search:findBooks("Dune")
      assert.are.equal(1, #results)
      assert.are.equal("Dune", results[1].title)
    end)
  end)

  describe("bookCatalog", function()
    it("formats standard catalog entries without series", function()
      local books = {
        {
          title = "Clean Code",
          authors = { "Robert C. Martin" },
          rootpath = "/mnt/books",
          lpath = "clean_code.epub",
          size = 1048576,
          tags = { "Programming", "Software" },
        },
      }

      local catalog = Search:bookCatalog(books)
      assert.is_table(catalog)
      assert.are.equal(1, #catalog)
      assert.are.equal("Clean Code - Robert C. Martin", catalog[1].text)
      assert.are.equal("/mnt/books/clean_code.epub", catalog[1].path)
      assert.is_string(catalog[1].info)
      assert.is_truthy(catalog[1].info:find("Title: Clean Code"))
      assert.is_truthy(catalog[1].info:find("Author%(s%): Robert C. Martin"))
      assert.is_truthy(catalog[1].info:find("Tags: Programming, Software"))
      assert.is_function(catalog[1].callback)
    end)

    it("handles subseries with fractional series index", function()
      local books = {
        {
          title = "The Novella",
          authors = { "Author Name" },
          rootpath = "/mnt/books",
          lpath = "novella.epub",
          size = 500000,
          series = "Epic Series",
          series_index = 2.5,
        },
      }

      local catalog = Search:bookCatalog(books, "series")
      assert.is_table(catalog)
      assert.are.equal(1, #catalog)
      -- Fractional series preserves minor index: "02.50 | The Novella - Author Name"
      assert.are.equal("02.50 | The Novella - Author Name", catalog[1].text)
    end)

    it(
      "formats book info when book.authors is nil without crashing (fails: line 148 nil author concat)",
      function()
        local book = {
          title = "Book Without Authors",
          rootpath = "/calibre",
          lpath = "authorless.epub",
          size = 2048,
          authors = nil,
        }
        local ok, res = pcall(function()
          return Search:bookCatalog({ book })
        end)
        -- Production bug in search.lua line 148:
        -- gettext("Author(s):") .. " " .. getEntries(book.authors) or "-"
        -- attempts string concatenation with nil before evaluating `or "-"`.
        assert.is_true(
          ok,
          "should not crash when book.authors is nil: " .. tostring(res)
        )
        assert.is_table(res)
        assert.is_truthy(res[1].info:find("Author%(s%): %-"))
      end
    )

    it(
      "strips trailing .00 for integer series without matching any character before 00 (fails: line 335 .00 pattern)",
      function()
        local book = {
          title = "Century Volume",
          authors = { "Alice" },
          rootpath = "/calibre",
          lpath = "vol100.epub",
          size = 4096,
          series = "My Series",
          series_index = 100,
        }
        local catalog = Search:bookCatalog({ book }, "series")
        -- Production bug in search.lua line 335:
        -- catalog[index].text = entry.text:gsub(".00", "", 1)
        -- In Lua patterns, "." matches any character, so ".00" matches "100" in "100.00",
        -- stripping the volume number and leaving ".00 | Century Volume - Alice" instead of "100 | Century Volume - Alice".
        assert.are.equal("100 | Century Volume - Alice", catalog[1].text)
      end
    )
  end)

  describe("onMenuHold", function()
    local old_show
    local shown_widget
    local FileManagerBookInfo
    local filemanagerutil

    before_each(function()
      FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
      filemanagerutil = require("apps/filemanager/filemanagerutil")

      old_show = UIManager.show
      UIManager.show = function(_, widget)
        shown_widget = widget
      end
    end)

    after_each(function()
      UIManager.show = old_show
      shown_widget = nil
    end)

    it("ignores items with empty or nil info", function()
      Search:onMenuHold({})
      assert.is_nil(shown_widget)

      Search:onMenuHold({ info = "" })
      assert.is_nil(shown_widget)
    end)

    it("shows InfoMessage dialog for valid item", function()
      local InfoMessage = require("ui/widget/infomessage")
      local old_info_new = InfoMessage.new
      local old_cover = FileManagerBookInfo.getCoverImage
      local old_status = filemanagerutil.getStatus
      local old_status_to_str = filemanagerutil.statusToString

      local info_args
      InfoMessage.new = function(_, args)
        info_args = args
        return { text = args.text, image = args.image }
      end

      FileManagerBookInfo.getCoverImage = function()
        return "mock_cover"
      end
      filemanagerutil.getStatus = function()
        return 1
      end
      filemanagerutil.statusToString = function()
        return "reading"
      end

      local item = {
        info = "Title: Test Book\nAuthor(s): Tester",
        path = "/test/path/book.epub",
      }

      Search:onMenuHold(item)

      InfoMessage.new = old_info_new
      FileManagerBookInfo.getCoverImage = old_cover
      filemanagerutil.getStatus = old_status
      filemanagerutil.statusToString = old_status_to_str

      assert.is_not_nil(shown_widget)
      assert.is_not_nil(info_args)
      assert.is_truthy(info_args.text:find("Title: Test Book"))
      assert.is_truthy(info_args.text:find("Status: reading"))
      assert.are.equal("mock_cover", info_args.image)
      assert.is_number(info_args.image_width)
      assert.is_number(info_args.image_height)
    end)
  end)

  describe("ShowSearch and close dialog lifecycle", function()
    local old_show
    local old_close
    local shown_widget
    local closed_widget

    before_each(function()
      old_show = UIManager.show
      old_close = UIManager.close
      UIManager.show = function(_, widget)
        shown_widget = widget
      end
      UIManager.close = function(_, widget)
        closed_widget = widget
      end
    end)

    after_each(function()
      UIManager.show = old_show
      UIManager.close = old_close
      shown_widget = nil
      closed_widget = nil
      Search.search_dialog = nil
      Search.search_value = nil
    end)

    it("creates and shows search InputDialog on ShowSearch", function()
      Search:ShowSearch()
      assert.is_not_nil(shown_widget)
      assert.are.equal(shown_widget, Search.search_dialog)
    end)

    it("closes search dialog on close()", function()
      Search:ShowSearch()
      Search.search_value = ""
      Search.lastsearch = "find"
      Search:close()
      assert.are.equal(Search.search_dialog, closed_widget)
    end)
  end)
end)
