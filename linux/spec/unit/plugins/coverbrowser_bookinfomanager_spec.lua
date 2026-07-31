describe("CoverBrowser BookInfoManager plugin module", function()
  local BookInfoManager, DataStorage

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    BookInfoManager:init()
  end)

  it("should expose BookInfoManager instance and methods", function()
    assert.is_table(BookInfoManager)
    assert.is_string(BookInfoManager.db_location)
  end)

  it("should handle book info database connection and size", function()
    BookInfoManager:createDB()
    BookInfoManager:openDbConnection()
    assert.is_not_nil(BookInfoManager.db_conn)

    local size_str = BookInfoManager:getDbSize()
    assert.is_string(size_str)

    BookInfoManager:closeDbConnection()
    assert.is_nil(BookInfoManager.db_conn)
  end)

  it("should handle getBookInfo queries for directory paths", function()
    BookInfoManager:openDbConnection()
    local book_info = BookInfoManager:getBookInfo(".", "non_existent_book.epub")
    assert.is_table(book_info)
    assert.is_true(book_info._is_directory or book_info._no_provider)
    BookInfoManager:closeDbConnection()
  end)
end)
