describe("bookinfomanager", function()
  local BookInfoManager
  local lfs = require("libs/libkoreader-lfs")

  setup(function()
    require("commonrequire")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
  end)

  teardown(function()
    package.loaded["plugins/coverbrowser.koplugin/bookinfomanager"] = nil
    if BookInfoManager then
      BookInfoManager:deleteDb()
    end
  end)

  before_each(function()
    if BookInfoManager then
      BookInfoManager:deleteDb()
    end
  end)

  describe("Database lifecycle & counts", function()
    it("returns 0 when DB does not exist", function()
      os.remove(BookInfoManager.db_location)
      assert.is_false(
        lfs.attributes(BookInfoManager.db_location, "mode") == "file"
      )
      assert.equal(0, BookInfoManager:getBookCount())
    end)

    it("returns 0 when DB is empty", function()
      BookInfoManager:openDbConnection()
      BookInfoManager:closeDbConnection()
      assert.is_true(
        lfs.attributes(BookInfoManager.db_location, "mode") == "file"
      )
      assert.equal(0, BookInfoManager:getBookCount())
    end)

    it("returns correct count when DB has items", function()
      BookInfoManager:openDbConnection()
      local conn = BookInfoManager.db_conn
      conn:exec(
        "INSERT INTO bookinfo (directory, filename) VALUES ('/books', 'book1.epub');"
      )
      conn:exec(
        "INSERT INTO bookinfo (directory, filename) VALUES ('/books', 'book2.epub');"
      )
      conn:exec(
        "INSERT INTO bookinfo (directory, filename) VALUES ('/books/dir', 'book3.epub');"
      )
      BookInfoManager:closeDbConnection()

      assert.equal(3, BookInfoManager:getBookCount())
    end)
  end)

  describe("Book Metadata & Settings", function()
    it("should open and close DB connection properly", function()
      BookInfoManager:openDbConnection()
      assert.is_not_nil(BookInfoManager.db_conn)
      assert.equal(0, BookInfoManager:getBookCount())
      BookInfoManager:closeDbConnection()
      assert.is_nil(BookInfoManager.db_conn)
    end)

    it("should correctly handle DB deletion", function()
      BookInfoManager:openDbConnection()
      assert.is_true(
        lfs.attributes(BookInfoManager.db_location, "mode") == "file"
      )
      BookInfoManager:closeDbConnection()
      BookInfoManager:deleteDb()
      assert.is_nil(lfs.attributes(BookInfoManager.db_location, "mode"))
    end)
  end)
end)
