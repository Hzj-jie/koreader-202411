-- luacheck: ignore 122
describe("Exporter Clip plugin module", function()
  local MyClipping, DocSettings, FileManagerBookInfo, util

  setup(function()
    require("commonrequire")
    MyClipping = require("plugins/exporter.koplugin/clip")
    DocSettings = require("docsettings")
    FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    util = require("util")
  end)

  describe("Clipping parsing and normalization", function()
    it("trims whitespace from text in getText", function()
      assert.are.equal("Hello World", MyClipping:getText("   Hello World   \n"))
      assert.are.equal("", MyClipping:getText("   \t  "))
      assert.are.equal("", MyClipping:getText(nil))
    end)

    it(
      "parses title and author from file name path in parseTitleFromPath",
      function()
        local title, author = MyClipping:parseTitleFromPath(
          "Pride and Prejudice - Jane Austen.epub"
        )
        assert.are.equal("Pride and Prejudice", title)
        assert.are.equal("Jane Austen", author)

        local title2, author2 =
          MyClipping:parseTitleFromPath("SingleTitle.epub")
        assert.are.equal("SingleTitle", title2)
        assert.are.equal("Unknown Author", author2)
      end
    )

    it("parses entry sort and location in getInfo", function()
      local info1 = MyClipping:getInfo(
        "- Your Highlight on Location 120-125 | Added on Monday, May 1, 2023 10:00:00 AM"
      )
      assert.are.equal("highlight", info1.sort)
      assert.are.equal("120-125", info1.location)
      assert.is_number(info1.time)

      local info2 = MyClipping:getInfo(
        "- Your Bookmark on Location 45 | Added on 2023-06-15 08:30:00"
      )
      assert.are.equal("bookmark", info2.sort)
      assert.are.equal("45", info2.location)
    end)

    it("parses valid date formats in getTime", function()
      local t1 = MyClipping:getTime("2023-05-01 10:15:30")
      assert.is_number(t1)
      local d1 = os.date("*t", t1)
      assert.are.equal(2023, d1.year)
      assert.are.equal(5, d1.month)
      assert.are.equal(1, d1.day)
      assert.are.equal(10, d1.hour)

      local t2 = MyClipping:getTime("May 1, 2023 09:30:00")
      assert.is_number(t2)
      local d2 = os.date("*t", t2)
      assert.are.equal(2023, d2.year)
      assert.are.equal(5, d2.month)
      assert.are.equal(1, d2.day)
      assert.are.equal(9, d2.hour)
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes getTime 12-hour AM/PM offset error turning 12 PM into 24:00 next day",
      function()
        -- 12:30:00 PM is noon on the same day (hour 12, day 1)
        local ts = MyClipping:getTime("2023-05-01 12:30:00 PM")
        assert.is_number(ts)

        local d = os.date("*t", ts)
        -- Due to blindly adding 12 to hour whenever 'PM' is matched:
        -- hour becomes 12 + 12 = 24, which os.time() normalizes to the next day (day 2, hour 0).
        -- In correct 12-to-24 hour conversion, 12 PM remains hour 12 on day 1.
        assert.are.equal(1, d.day)
        assert.are.equal(12, d.hour)
      end
    )

    it(
      "fails: exposes getClippingsFromBook not setting output_filename",
      function()
        local mock_doc_path = "/tmp/test_book_clippings.epub"
        local orig_open = DocSettings.open
        local orig_extend = FileManagerBookInfo.extendProps

        DocSettings.open = function()
          return {
            readTableRef = function(_, key)
              if key == "doc_props" then
                return { title = "Test Book Title", authors = "Author Name" }
              end
              return {}
            end,
            read = function(_, key)
              if key == "doc_pages" then
                return 350
              end
              return nil
            end,
            has = function()
              return false
            end,
          }
        end

        FileManagerBookInfo.extendProps = function(props)
          return props
        end

        finally(function()
          DocSettings.open = orig_open
          FileManagerBookInfo.extendProps = orig_extend
        end)

        local clippings = {}
        MyClipping:getClippingsFromBook(clippings, mock_doc_path)

        local book = clippings["Test Book Title"]
        assert.is_not_nil(book)
        assert.are.equal("Test Book Title", book.title)
        assert.are.equal("Author Name", book.author)

        -- parseCurrentDoc sets: output_filename = util.getSafeFilename(title)
        -- getClippingsFromBook omits output_filename entirely, leaving it nil,
        -- which causes BaseExporter:getFilePath() to produce a filename with '-nil.ext'.
        assert.is_not_nil(
          book.output_filename,
          "getClippingsFromBook should set output_filename for exported clipping targets"
        )
      end
    )
  end)
end)
