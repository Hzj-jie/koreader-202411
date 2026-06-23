describe("bookinfomanager", function()
  local BookInfoManager
  local lfs = require("libs/libkoreader-lfs")

  setup(function()
    require("commonrequire")
    -- Load BookInfoManager
    -- We need to add plugins/coverbrowser.koplugin to package.path to load it
    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. package.path
    BookInfoManager = require("bookinfomanager")
  end)

  teardown(function()
    package.loaded["bookinfomanager"] = nil
    -- Clean up DB file if it exists
    if BookInfoManager then
      BookInfoManager:deleteDb()
    end
  end)

  before_each(function()
    if BookInfoManager then
      BookInfoManager:deleteDb()
    end
  end)

  it("returns 0 when DB does not exist", function()
    -- Ensure DB does not exist
    os.remove(BookInfoManager.db_location)
    assert.is_false(lfs.attributes(BookInfoManager.db_location, "mode") == "file")

    assert.equal(0, BookInfoManager:getBookCount())
  end)

  it("returns 0 when DB is empty", function()
    -- This will create the DB but keep it empty
    BookInfoManager:openDbConnection()
    BookInfoManager:closeDbConnection()
    assert.is_true(lfs.attributes(BookInfoManager.db_location, "mode") == "file")

    assert.equal(0, BookInfoManager:getBookCount())
  end)

  it("returns correct count when DB has items", function()
    BookInfoManager:openDbConnection()
    -- Insert dummy data
    -- directory and filename are NOT NULL in schema
    local conn = BookInfoManager.db_conn
    conn:exec("INSERT INTO bookinfo (directory, filename) VALUES ('/books', 'book1.epub');")
    conn:exec("INSERT INTO bookinfo (directory, filename) VALUES ('/books', 'book2.epub');")
    conn:exec("INSERT INTO bookinfo (directory, filename) VALUES ('/books/dir', 'book3.epub');")
    BookInfoManager:closeDbConnection()

    assert.equal(3, BookInfoManager:getBookCount())
  end)
end)
