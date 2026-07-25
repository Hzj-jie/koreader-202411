describe("Exporter clip module", function()
  local MyClipping
  local DataStorage
  local DocSettings
  local DocumentRegistry

  setup(function()
    require("commonrequire")
    MyClipping = require("plugins/exporter.koplugin/clip")
    DataStorage = require("datastorage")
    DocSettings = require("docsettings")
    DocumentRegistry = require("document/documentregistry")
  end)

  before_each(function()
    G_reader_settings:save("exporter", {})
  end)

  describe("new", function()
    it("should initialize with default path", function()
      local clipping = MyClipping:new()
      assert.is.not_nil(clipping)
      assert.are.equal(
        "/mnt/us/documents/My Clippings.txt",
        clipping.my_clippings
      )
    end)

    it("should accept custom options", function()
      local clipping =
        MyClipping:new({ my_clippings = "/tmp/custom_clippings.txt" })
      assert.are.equal("/tmp/custom_clippings.txt", clipping.my_clippings)
    end)
  end)

  describe("parseTitleFromPath", function()
    it("should parse title and author in Title (Author) format", function()
      local title, author = MyClipping:parseTitleFromPath(
        "The Great Gatsby (F. Scott Fitzgerald).epub"
      )
      assert.are.equal("The Great Gatsby", title)
      assert.are.equal("F. Scott Fitzgerald", author)
    end)

    it("should parse title and author in Title - Author format", function()
      local title, author =
        MyClipping:parseTitleFromPath("1984 - George Orwell.pdf")
      assert.are.equal("1984", title)
      assert.are.equal("George Orwell", author)
    end)

    it("should handle missing author", function()
      local title, author = MyClipping:parseTitleFromPath("Just Title.mobi")
      assert.are.equal("Just Title", title)
      assert.are.equal("Unknown Author", author)
    end)

    it("should handle uppercase extensions", function()
      local title, author =
        MyClipping:parseTitleFromPath("Sample Book (Author).PDF")
      assert.are.equal("Sample Book", title)
      assert.are.equal("Author", author)
    end)

    it("should handle empty or nil line", function()
      local title, author = MyClipping:parseTitleFromPath("")
      assert.are.equal("Unknown Book", title)
      assert.are.equal("Unknown Author", author)
    end)
  end)

  describe("getTime", function()
    it("should parse Chinese date format", function()
      local time = MyClipping:getTime("2024年05月15日 14:30:00")
      assert.is.not_nil(time)
      local t = os.date("*t", time)
      assert.are.equal(2024, t.year)
      assert.are.equal(5, t.month)
      assert.are.equal(15, t.day)
      assert.are.equal(14, t.hour)
      assert.are.equal(30, t.min)
      assert.are.equal(0, t.sec)
    end)

    it("should parse ISO date format", function()
      local time = MyClipping:getTime("2024-05-15 08:20:10")
      assert.is.not_nil(time)
      local t = os.date("*t", time)
      assert.are.equal(2024, t.year)
      assert.are.equal(5, t.month)
      assert.are.equal(15, t.day)
      assert.are.equal(8, t.hour)
    end)

    it("should parse English date format with PM", function()
      local time =
        MyClipping:getTime("Added on Monday, April 21, 2014 10:08:07 PM")
      assert.is.not_nil(time)
      local t = os.date("*t", time)
      assert.are.equal(2014, t.year)
      assert.are.equal(4, t.month)
      assert.are.equal(21, t.day)
      assert.are.equal(22, t.hour)
      assert.are.equal(8, t.min)
      assert.are.equal(7, t.sec)
    end)

    it("should return nil for invalid format or nil input", function()
      assert.is_nil(MyClipping:getTime(nil))
      assert.is_nil(MyClipping:getTime("Invalid date string"))
    end)
  end)

  describe("getInfo", function()
    it("should parse highlight line with location and timestamp", function()
      local info = MyClipping:getInfo(
        "Your Highlight on Page 123 | Added on 2024-05-15 14:30:00"
      )
      assert.are.equal("highlight", info.sort)
      assert.are.equal("123", info.location)
      assert.is.not_nil(info.time)
    end)

    it("should parse Chinese highlight line", function()
      local info = MyClipping:getInfo(
        "您的标注在位置 456-458 | 添加于 2024年05月15日 14:30:00"
      )
      assert.are.equal("highlight", info.sort)
      assert.are.equal("456-458", info.location)
      assert.is.not_nil(info.time)
    end)

    it("should parse note and bookmark lines", function()
      local info_note = MyClipping:getInfo(
        "Your Note on Page 50 | Added on 2024-05-15 14:30:00"
      )
      assert.are.equal("note", info_note.sort)

      local info_bm = MyClipping:getInfo(
        "Your Bookmark on Page 10 | Added on 2024-05-15 14:30:00"
      )
      assert.are.equal("bookmark", info_bm.sort)
    end)
  end)

  describe("getText", function()
    it("should trim whitespace", function()
      assert.are.equal("Hello World", MyClipping:getText("   Hello World   "))
      assert.are.equal("", MyClipping:getText(nil))
      assert.are.equal("", MyClipping:getText("   "))
    end)
  end)

  describe("parseMyClippings", function()
    it("should return empty table if file does not exist", function()
      local clipper = MyClipping:new({ my_clippings = "/nonexistent/path.txt" })
      local clippings = clipper:parseMyClippings()
      assert.are.same({}, clippings)
    end)

    it("should parse a valid Kindle My Clippings file", function()
      local tmp_file = DataStorage:getDataDir() .. "/test_my_clippings.txt"
      local f = io.open(tmp_file, "w")
      f:write("Sample Book (Test Author)\n")
      f:write(
        "- Your Highlight on Page 123 | Added on Monday, April 21, 2014 10:08:07 PM\n"
      )
      f:write("\n")
      f:write("This is a sample highlight text.\n")
      f:write("==========\n")
      f:close()

      local clipper = MyClipping:new({ my_clippings = tmp_file })
      local clippings = clipper:parseMyClippings()
      os.remove(tmp_file)

      assert.is.not_nil(clippings["Sample Book"])
      assert.are.equal("Sample Book", clippings["Sample Book"].title)
      assert.are.equal("Test Author", clippings["Sample Book"].author)
      assert.are.equal(1, #clippings["Sample Book"])
      assert.are.equal(
        "This is a sample highlight text.",
        clippings["Sample Book"][1][1].text
      )
      assert.are.equal("123", clippings["Sample Book"][1][1].page)
    end)
  end)

  describe("parseAnnotations", function()
    it("should parse annotations into book table", function()
      local annotations = {
        {
          pageref = 12,
          datetime = "2024-05-15 10:00:00",
          text = "  Annotation text  ",
          note = "  My note  ",
          chapter = "Chapter 1",
          drawer = "lighten",
          color = "yellow",
        },
      }
      local book = {}
      MyClipping:parseAnnotations(annotations, book)
      assert.are.equal(1, #book)
      local clipping = book[1][1]
      assert.are.equal("highlight", clipping.sort)
      assert.are.equal(12, clipping.page)
      assert.are.equal("Annotation text", clipping.text)
      assert.are.equal("My note", clipping.note)
      assert.are.equal("Chapter 1", clipping.chapter)
      assert.are.equal("lighten", clipping.drawer)
      assert.are.equal("yellow", clipping.color)
    end)

    it(
      "should skip annotations when drawer style is disabled in settings",
      function()
        G_reader_settings:save("exporter", {
          highlight_styles = {
            lighten = false,
          },
        })
        local annotations = {
          {
            pageref = 12,
            datetime = "2024-05-15 10:00:00",
            text = "Disabled drawer text",
            drawer = "lighten",
          },
          {
            pageref = 15,
            datetime = "2024-05-15 10:05:00",
            text = "Enabled drawer text",
            drawer = "underscore",
          },
        }
        local book = {}
        MyClipping:parseAnnotations(annotations, book)
        assert.are.equal(1, #book)
        assert.are.equal("Enabled drawer text", book[1][1].text)
      end
    )
  end)

  describe("parseHighlight", function()
    it("should process highlights and associate matching bookmarks", function()
      local datetime = "2024-05-15 12:00:00"
      local highlights = {
        [5] = {
          {
            datetime = datetime,
            text = "Highlight content",
            drawer = "lighten",
            chapter = "Chapter 2",
          },
        },
      }
      local bookmarks = {
        {
          datetime = datetime,
          text = "User note for highlight",
        },
      }
      local book = {}
      MyClipping:parseHighlight(highlights, bookmarks, book)
      assert.are.equal(1, #book)
      local clipping = book[1][1]
      assert.are.equal("Highlight content", clipping.text)
      assert.are.equal("User note for highlight", clipping.note)
      assert.are.equal(5, clipping.page)
    end)

    it("should extract quote from auto-text formatted bookmark", function()
      local datetime = "2024-05-15 12:00:00"
      local highlights = {
        [5] = {
          {
            datetime = datetime,
            text = "Highlight content",
            drawer = "lighten",
          },
        },
      }
      local bookmarks = {
        {
          datetime = datetime,
          text = "Page 5 Note text @ 2024-05-15 12:00:00",
        },
      }
      local book = {}
      MyClipping:parseHighlight(highlights, bookmarks, book)
      assert.are.equal(1, #book)
      assert.are.equal("Note text", book[1][1].note)
    end)

    it("should sort highlights according to bookmark indexes", function()
      local dt1 = "2024-05-15 10:00:00"
      local dt2 = "2024-05-15 11:00:00"
      local highlights = {
        [1] = {
          { datetime = dt1, text = "First highlight", drawer = "lighten" },
        },
        [2] = {
          { datetime = dt2, text = "Second highlight", drawer = "lighten" },
        },
      }
      local bookmarks = {
        { datetime = dt2, text = "Bookmark 2" },
        { datetime = dt1, text = "Bookmark 1" },
      }
      local book = {}
      MyClipping:parseHighlight(highlights, bookmarks, book)
      assert.are.equal(2, #book)
      assert.are.equal("First highlight", book[1][1].text)
      assert.are.equal("Second highlight", book[2][1].text)
    end)

    it(
      "should handle reflowing mode coordinates when pos0.page and pos1.page are nil",
      function()
        local orig_open = DocumentRegistry.openDocument
        DocumentRegistry.openDocument = function(self, path)
          return {
            clipPagePNGString = function(self_doc, pos0, pos1, pboxes, drawer)
              return "mock_png_binary_data"
            end,
            close = function() end,
          }
        end

        local datetime = "2024-05-15 12:00:00"
        local highlights = {
          [3] = {
            {
              datetime = datetime,
              text = "",
              drawer = "lighten",
              pos0 = { x = 10, y = 20 },
              pos1 = { x = 100, y = 200 },
            },
          },
        }
        local bookmarks = {
          { datetime = datetime, text = "Bookmark note" },
        }
        local book = { file = "/dummy/path.epub" }
        MyClipping:parseHighlight(highlights, bookmarks, book)

        DocumentRegistry.openDocument = orig_open

        assert.are.equal(1, #book)
        local clipping = book[1][1]
        assert.is.not_nil(clipping.image)
        assert.are.equal("mock_png_binary_data", clipping.image.png)
        assert.is.not_nil(clipping.image.hash)
      end
    )

    it("should handle orphan highlights without bookmarks", function()
      local highlights = {
        [8] = {
          {
            datetime = "2024-05-15 14:00:00",
            text = "Orphan highlight",
            drawer = "lighten",
          },
        },
      }
      local bookmarks = {}
      local book = {}
      MyClipping:parseHighlight(highlights, bookmarks, book)
      assert.are.equal(1, #book)
      assert.are.equal("Orphan highlight", book[1][1].text)
    end)
  end)

  describe("getImage", function()
    it(
      "should return image png and hash for valid document image pos",
      function()
        local orig_open = DocumentRegistry.openDocument
        DocumentRegistry.openDocument = function(self, path)
          return {
            clipPagePNGString = function(self_doc, pos0, pos1, pboxes, drawer)
              return "mock_png_data"
            end,
            close = function() end,
          }
        end

        local image_info = {
          file = "/dummy/doc.epub",
          pos0 = { page = 1, x = 0, y = 0 },
          pos1 = { page = 1, x = 100, y = 100 },
          drawer = "lighten",
        }
        local result = MyClipping:getImage(image_info)

        DocumentRegistry.openDocument = orig_open

        assert.is.not_nil(result)
        assert.are.equal("mock_png_data", result.png)
        assert.is.not_nil(result.hash)
      end
    )

    it("should return nil for non-existent document file", function()
      local orig_open = DocumentRegistry.openDocument
      DocumentRegistry.openDocument = function(self, path)
        return nil
      end

      local image_info = {
        file = "/nonexistent/path.epub",
        pos0 = { page = 1, x = 0, y = 0 },
        pos1 = { page = 1, x = 100, y = 100 },
      }
      local result = MyClipping:getImage(image_info)

      DocumentRegistry.openDocument = orig_open

      assert.is_nil(result)
    end)
  end)

  describe("getTitleAuthor", function()
    it("should prefer props title and author if present", function()
      local title, author =
        MyClipping:getTitleAuthor("/path/to/Book (Author).epub", {
          title = "Prop Title",
          authors = "Prop Author",
        })
      assert.are.equal("Prop Title", title)
      assert.are.equal("Prop Author", author)
    end)

    it("should fall back to parsed path when props are empty", function()
      local title, author =
        MyClipping:getTitleAuthor("/path/to/Book (Author).epub", {})
      assert.are.equal("Book", title)
      assert.are.equal("Author", author)
    end)
  end)

  describe("getClippingsFromBook and parseFiles", function()
    it("should read clippings from sidecar file using DocSettings", function()
      local doc_path = DataStorage:getDataDir()
        .. "/test_book (Test Author).epub"
      local doc_settings = DocSettings:open(doc_path)
      doc_settings:save(
        "doc_props",
        { title = "Sidecar Book", authors = "Sidecar Author" }
      )
      doc_settings:save("doc_pages", 150)
      doc_settings:save("annotations", {
        {
          pageref = 7,
          datetime = "2024-05-15 10:00:00",
          text = "Sidecar highlight text",
          drawer = "lighten",
        },
      })
      doc_settings:flush()

      local files = { [doc_path] = true }
      local clippings = MyClipping:parseFiles(files)

      doc_settings:purge()
      os.remove(doc_path)

      assert.is.not_nil(clippings["Sidecar Book"])
      assert.are.equal("Sidecar Book", clippings["Sidecar Book"].title)
      assert.are.equal("Sidecar Author", clippings["Sidecar Book"].author)
      assert.are.equal(150, clippings["Sidecar Book"].number_of_pages)
      assert.are.equal(1, #clippings["Sidecar Book"])
      assert.are.equal(
        "Sidecar highlight text",
        clippings["Sidecar Book"][1][1].text
      )
    end)
  end)

  describe("parseHistory", function()
    it("should parse history entries with sidecar files", function()
      local readhistory = require("readhistory")
      local doc_path = DataStorage:getDataDir()
        .. "/history_book (History Author).epub"
      local doc_settings = DocSettings:open(doc_path)
      doc_settings:save(
        "doc_props",
        { title = "History Book", authors = "History Author" }
      )
      doc_settings:save("doc_pages", 50)
      doc_settings:save("annotations", {
        {
          pageref = 3,
          datetime = "2024-05-15 11:00:00",
          text = "History highlight text",
          drawer = "lighten",
        },
      })
      doc_settings:flush()

      table.insert(readhistory.hist, 1, { file = doc_path })

      local clippings = MyClipping:parseHistory()

      table.remove(readhistory.hist, 1)
      doc_settings:purge()
      os.remove(doc_path)

      assert.is.not_nil(clippings["History Book"])
      assert.are.equal(
        "History highlight text",
        clippings["History Book"][1][1].text
      )
    end)
  end)

  describe("parseCurrentDoc", function()
    it("should extract clippings from current document view", function()
      local view = {
        document = {
          file = "/path/to/CurrentBook (Author).epub",
          info = {
            number_of_pages = 250,
          },
        },
        ui = {
          doc_props = {},
          annotation = {
            annotations = {
              {
                pageref = 5,
                datetime = "2024-05-15 10:00:00",
                text = "Current doc highlight",
                drawer = "lighten",
              },
            },
          },
        },
      }

      local clippings = MyClipping:parseCurrentDoc(view)
      assert.is.not_nil(clippings["CurrentBook"])
      assert.are.equal(
        "/path/to/CurrentBook (Author).epub",
        clippings["CurrentBook"].file
      )
      assert.are.equal("CurrentBook", clippings["CurrentBook"].title)
      assert.are.equal("Author", clippings["CurrentBook"].author)
      assert.are.equal(250, clippings["CurrentBook"].number_of_pages)
      assert.are.equal(1, #clippings["CurrentBook"])
      assert.are.equal(
        "Current doc highlight",
        clippings["CurrentBook"][1][1].text
      )
    end)
  end)
end)
