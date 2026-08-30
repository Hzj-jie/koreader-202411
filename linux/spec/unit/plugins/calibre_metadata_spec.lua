describe("Calibre Metadata plugin module", function()
  local CalibreMetadata, rapidjson

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    rapidjson = require("rapidjson")
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

    meta:removeBook("books/test.epub")
    assert.are.equal(0, #meta.books)
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
end)
