describe("Calibre Metadata plugin module", function()
  local CalibreMetadata, rapidjson, util

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    rapidjson = require("rapidjson")
    util = require("util")
    CalibreMetadata = require("plugins/calibre.koplugin/metadata")
  end)

  it("should add, retrieve, and remove books in metadata instance", function()
    local meta = setmetatable({
      books = rapidjson.array({}),
    }, { __index = CalibreMetadata })

    local book = {
      uuid = "uuid-12345",
      lpath = "books/test.epub",
      title = "Test Book",
      authors = { "Author Name" },
      size = 1024,
    }

    meta:addBook(book)
    assert.are.equal(1, #meta.books)

    local uuid, index = meta:getBookUuid("books/test.epub")
    assert.are.equal("uuid-12345", uuid)
    assert.are.equal(1, index)

    local book_data = meta:getBookMetadata(1)
    assert.is_table(book_data)
    assert.are.equal("Test Book", book_data.title)

    local book_id = meta:getBookId(1)
    assert.are.equal(1, book_id.priKey)
    assert.are.equal("uuid-12345", book_id.uuid)
    assert.are.equal("books/test.epub", book_id.lpath)

    -- Updating existing book replaces at same index
    local updated_book = {
      uuid = "uuid-12345",
      lpath = "books/test.epub",
      title = "Updated Title",
      authors = { "Author Name" },
      size = 2048,
    }
    meta:addBook(updated_book)
    assert.are.equal(1, #meta.books)
    assert.are.equal("Updated Title", meta:getBookMetadata(1).title)

    meta:removeBook("books/test.epub")
    assert.are.equal(0, #meta.books)
    assert.are.equal("none", meta:getBookUuid("books/test.epub"))
  end)

  it("should load and save device info JSON", function()
    local tmp_file = os.tmpname()
    local meta = setmetatable({
      drive = rapidjson.array({}),
      driveinfo = tmp_file,
    }, { __index = CalibreMetadata })

    meta:saveDeviceInfo({ device_name = "KOReader-Test", drive_id = "123" })

    local loaded = meta:loadDeviceInfo(tmp_file)
    assert.is_table(loaded)
    assert.are.equal("KOReader-Test", loaded.device_name)

    os.remove(tmp_file)
  end)

  it("should load and save book list JSON file", function()
    local tmp_file = os.tmpname()
    local meta = setmetatable({
      books = rapidjson.array({
        { uuid = "abc", lpath = "a.epub", title = "A" },
      }),
      metadata = tmp_file,
    }, { __index = CalibreMetadata })

    meta:saveBookList()

    local loaded_books = meta:loadBookList()
    assert.is_table(loaded_books)

    os.remove(tmp_file)
  end)

  it("should clean unused fields and reset temporary state", function()
    local tmp_file = os.tmpname()
    local meta = setmetatable({
      books = rapidjson.array({
        {
          uuid = "uuid-1",
          lpath = "a.epub",
          title = "Book A",
          extra_garbage = "unused_field",
        },
      }),
      metadata = tmp_file,
      path = "/calibre",
      driveinfo = "/calibre/driveinfo.calibre",
    }, { __index = CalibreMetadata })

    -- Normal cleanUnused dumps to file
    meta:cleanUnused(false)
    assert.is_nil(meta.books[1].extra_garbage)
    assert.are.equal("Book A", meta.books[1].title)

    -- Search cleanUnused does not dump
    meta:cleanUnused(true)
    assert.is_nil(meta.books[1].uuid) -- uuid excluded from search_used_metadata

    -- Reset state
    meta:clean()
    assert.are.equal(0, #meta.books)
    assert.is_nil(meta.path)
    assert.is_nil(meta.driveinfo)
    assert.is_nil(meta.metadata)

    os.remove(tmp_file)
  end)

  it(
    "should prune all deleted books when consecutive books are missing [exposes production bug in CalibreMetadata:prune()]",
    function()
      local old_exists = util.fileExists
      local saved = false

      local meta = setmetatable({
        path = "/fake/calibre",
        metadata = "/fake/calibre/metadata.calibre",
        books = rapidjson.array({
          { uuid = "uuid-1", lpath = "missing1.epub", title = "Missing 1" },
          { uuid = "uuid-2", lpath = "missing2.epub", title = "Missing 2" },
          { uuid = "uuid-3", lpath = "present3.epub", title = "Present 3" },
        }),
        saveBookList = function()
          saved = true
        end,
      }, { __index = CalibreMetadata })

      util.fileExists = function(filepath)
        if filepath:find("missing1.epub", 1, true) then
          return false
        elseif filepath:find("missing2.epub", 1, true) then
          return false
        end
        return true
      end

      -- Production bug: prune() uses ipairs(self.books) while calling self:removeBook(),
      -- mutating self.books in-place and skipping the consecutive missing2.epub
      local pruned_count = meta:prune()
      assert.are.equal(2, pruned_count)
      assert.are.equal(1, #meta.books)
      assert.are.equal("uuid-3", meta.books[1].uuid)
      assert.are.equal("none", meta:getBookUuid("missing2.epub"))
      assert.is_true(saved)

      util.fileExists = old_exists
    end
  )
end)
