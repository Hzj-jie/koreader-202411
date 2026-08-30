describe("Coverbrowser BookInfoManager module", function()
  local BookInfoManager, DataStorage, Device, SQ3, util

  setup(function()
    require("commonrequire")
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    Device = require("device")
    SQ3 = require("lua-ljsqlite3/init")
    util = require("util")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    BookInfoManager:init()
  end)

  after_each(function()
    BookInfoManager:closeDbConnection()
  end)

  describe("Initialization & Properties", function()
    it("should expose BookInfoManager class table and correct properties", function()
      assert.is_table(BookInfoManager)
      assert.is_string(BookInfoManager.db_location)
      assert.is_number(BookInfoManager.max_extract_tries)
      assert.is_number(BookInfoManager.subprocesses_collect_interval)
    end)
  end)

  describe("Database Lifecycle & Utilities", function()
    it("should create database, connect, get size and book count, and delete DB", function()
      BookInfoManager:createDB()
      assert.is_true(BookInfoManager.db_created)

      BookInfoManager:openDbConnection()
      assert.is_not_nil(BookInfoManager.db_conn)

      local count = BookInfoManager:getBookCount()
      assert.is_number(count)

      local size_str = BookInfoManager:getDbSize()
      assert.is_string(size_str)

      local compact_res = BookInfoManager:compactDb()
      assert.is_string(compact_res)

      BookInfoManager:closeDbConnection()
      assert.is_nil(BookInfoManager.db_conn)

      BookInfoManager:deleteDb()
      assert.is_false(BookInfoManager.db_created)
    end)
  end)

  describe("Settings Management", function()
    it("should load, save, get, and toggle settings in DB config table", function()
      BookInfoManager:createDB()
      BookInfoManager:openDbConnection()

      BookInfoManager:save("test_key", "test_val")
      local val = BookInfoManager:getSetting("test_key")
      assert.are_equal("test_val", val)

      BookInfoManager:save("test_num", 42)
      local num_val = BookInfoManager:getSetting("test_num")
      assert.are_equal(42, num_val)

      BookInfoManager:save("test_bool", true)
      local bool_val = BookInfoManager:getSetting("test_bool")
      assert.are_equal("Y", bool_val)

      local toggled = BookInfoManager:toggleSetting("test_toggle")
      assert.is_boolean(toggled)
      local toggled_val = BookInfoManager:getSetting("test_toggle")
      assert.are_equal("Y", toggled_val)

      local toggled2 = BookInfoManager:toggleSetting("test_toggle")
      assert.is_false(toggled2)
    end)
  end)

  describe("Book Info Records Operations", function()
    it("should return pseudo-bookinfo for directories or non-provider files", function()
      local dir_info = BookInfoManager:getBookInfo("/tmp", false)
      assert.is_table(dir_info)
      assert.is_true(dir_info._is_directory)
      assert.are_equal("Y", dir_info.cover_fetched)

      local noprov_info = BookInfoManager:getBookInfo("/tmp/test_nonexistent.xyz123", false)
      assert.is_table(noprov_info)
      assert.is_true(noprov_info._no_provider)
    end)

    it("should set properties, query, and delete book info records", function()
      BookInfoManager:createDB()
      BookInfoManager:openDbConnection()

      local dummy_file = "/tmp/test_bookinfo_dummy.epub"
      local dir, fn = util.splitFilePathName(dummy_file)

      -- Insert a record directly via set_stmt
      local dbrow = {
        directory = dir,
        filename = fn,
        filesize = 12345,
        filemtime = 1000,
        in_progress = 0,
        unsupported = nil,
        cover_fetched = "Y",
        has_meta = "Y",
        has_cover = nil,
        cover_sizetag = nil,
        ignore_meta = nil,
        ignore_cover = nil,
        pages = 100,
        title = "Test Book",
        authors = "Test Author",
        series = "Test Series",
        series_index = 1.0,
        language = "en",
        keywords = "test",
        description = "Test Description",
        cover_w = nil,
        cover_h = nil,
        cover_bb_type = nil,
        cover_bb_stride = nil,
        cover_bb_data = nil,
      }
      local BOOKINFO_COLS_SET = {
        "directory", "filename", "filesize", "filemtime",
        "in_progress", "unsupported", "cover_fetched",
        "has_meta", "has_cover", "cover_sizetag",
        "ignore_meta", "ignore_cover", "pages",
        "title", "authors", "series", "series_index",
        "language", "keywords", "description",
        "cover_w", "cover_h", "cover_bb_type", "cover_bb_stride", "cover_bb_data",
      }
      for num, col in ipairs(BOOKINFO_COLS_SET) do
        BookInfoManager.set_stmt:bind1(num, dbrow[col])
      end
      BookInfoManager.set_stmt:step()
      BookInfoManager.set_stmt:clearbind():reset()

      -- Query getBookInfo
      local info = BookInfoManager:getBookInfo(dummy_file, false)
      assert.is_table(info)
      assert.are_equal("Test Book", info.title)
      assert.are.equal(100, info.pages)

      -- Update property
      BookInfoManager:setBookInfoProperties(dummy_file, { title = "Updated Title", ignore_meta = false })
      local updated_info = BookInfoManager:getBookInfo(dummy_file, false)
      assert.are_equal("Updated Title", updated_info.title)

      -- Prune non-existent entries
      local prune_msg = BookInfoManager:removeNonExistantEntries()
      assert.is_string(prune_msg)

      -- Delete info
      BookInfoManager:deleteBookInfo(dummy_file)
      local deleted_info = BookInfoManager:getBookInfo(dummy_file, false)
      assert.is_nil(deleted_info)
    end)
  end)

  describe("Cover scaling and Subprocess helpers", function()
    it("should calculate cached cover size and check validity", function()
      if type(BookInfoManager.getCachedCoverSize) == "function" then
        local w, h = BookInfoManager.getCachedCoverSize(800, 1200, 400, 600)
        assert.is_number(w)
        assert.is_number(h)
      end

      local fake_info = {
        has_cover = "Y",
        cover_w = 100,
        cover_h = 150,
        cover_sizetag = "100x150",
      }
      local invalid = BookInfoManager.isCachedCoverInvalid(fake_info, { max_cover_w = 200, max_cover_h = 300 })
      assert.truthy(invalid == nil or type(invalid) == "boolean")
    end)

    it("should store and retrieve compressed cover data with get_cover = true", function()
      BookInfoManager:createDB()
      BookInfoManager:openDbConnection()

      local Blitbuffer = require("ffi/blitbuffer")
      local zstd = require("ffi/zstd")

      local dummy_file = "/tmp/test_cover_compressed.epub"
      local dir, fn = util.splitFilePathName(dummy_file)

      local sample_bb = Blitbuffer.new(20, 30, Blitbuffer.TYPE_BB8)
      local cover_size = sample_bb.stride * sample_bb.h
      local comp_data, comp_size = zstd.zstd_compress(sample_bb.data, cover_size)

      local dbrow = {
        directory = dir,
        filename = fn,
        filesize = 5000,
        filemtime = 1000,
        in_progress = 0,
        unsupported = nil,
        cover_fetched = "Y",
        has_meta = "Y",
        has_cover = "Y",
        cover_sizetag = "20x30",
        ignore_meta = nil,
        ignore_cover = nil,
        pages = 50,
        title = "Cover Book",
        authors = "Cover Author",
        series = nil,
        series_index = nil,
        language = "en",
        keywords = nil,
        description = "Has Cover",
        cover_w = 20,
        cover_h = 30,
        cover_bb_type = tonumber(sample_bb:getType()),
        cover_bb_stride = tonumber(sample_bb.stride),
        cover_bb_data = SQ3.blob(comp_data, comp_size),
      }
      local BOOKINFO_COLS_SET = {
        "directory", "filename", "filesize", "filemtime",
        "in_progress", "unsupported", "cover_fetched",
        "has_meta", "has_cover", "cover_sizetag",
        "ignore_meta", "ignore_cover", "pages",
        "title", "authors", "series", "series_index",
        "language", "keywords", "description",
        "cover_w", "cover_h", "cover_bb_type", "cover_bb_stride", "cover_bb_data",
      }
      for num, col in ipairs(BOOKINFO_COLS_SET) do
        BookInfoManager.set_stmt:bind1(num, dbrow[col])
      end
      BookInfoManager.set_stmt:step()
      BookInfoManager.set_stmt:clearbind():reset()

      -- Query with get_cover = true
      local info_with_cover = BookInfoManager:getBookInfo(dummy_file, true)
      assert.is_table(info_with_cover)
      assert.are.equal("Cover Book", info_with_cover.title)
      assert.is_not_nil(info_with_cover.cover_bb)
      assert.are.equal(20, info_with_cover.cover_bb.w)
      assert.are.equal(30, info_with_cover.cover_bb.h)

      sample_bb:free()
      if info_with_cover.cover_bb then
        info_with_cover.cover_bb:free()
      end
    end)

    it("should handle subprocess tracking and extraction helpers safely", function()
      local lfs = require("libs/libkoreader-lfs")
      local test_dir = "/tmp/test_koreader_cov_dir"
      lfs.mkdir(test_dir)

      assert.is_false(BookInfoManager:isExtractingInBackground())
      BookInfoManager:terminateBackgroundJobs()
      BookInfoManager:collectSubprocesses()
      BookInfoManager:cleanUp()
      assert.is_false(BookInfoManager:isExtractingInBackground())

      -- Test extractBooksInDirectory
      BookInfoManager:extractBooksInDirectory(test_dir, { max_cover_w = 100, max_cover_h = 150 })

      -- Test extractInBackground with empty list
      BookInfoManager:extractInBackground({})
    end)

    it("should handle extractBookInfo directly with documents and handle error states", function()
      BookInfoManager:createDB()
      BookInfoManager:openDbConnection()

      local sample_file = "origin/test/epub2-conform/Html401/10_2-BF-01.epub"
      if not lfs.attributes(sample_file) then
        sample_file = "/tmp/test_dummy_book.epub"
        local f = io.open(sample_file, "w")
        if f then f:write("dummy"); f:close() end
      end

      -- Extract book info with cover specs
      local ok = BookInfoManager:extractBookInfo(sample_file, { max_cover_w = 100, max_cover_h = 150 })
      assert.is_boolean(ok)

      -- Query the extracted book info
      local info = BookInfoManager:getBookInfo(sample_file, false)
      assert.is_table(info)

      -- Test max_extract_tries exceeded
      local dir, fn = util.splitFilePathName(sample_file)
      BookInfoManager:setBookInfoProperties(sample_file, { in_progress = BookInfoManager.max_extract_tries + 1 })
      BookInfoManager:extractBookInfo(sample_file, nil)
      local tried_info = BookInfoManager:getBookInfo(sample_file, false)
      assert.is_table(tried_info)
      assert.are.equal(0, tried_info.in_progress)

      -- Test unreadable document
      local unreadable_file = "/tmp/unreadable_test.unknown_ext"
      local uf = io.open(unreadable_file, "w")
      if uf then uf:write("corrupt header"); uf:close() end
      local DocumentRegistry = require("document/documentregistry")
      local open_stub = stub(DocumentRegistry, "openDocument", function() return nil end)
      local unread_ok = BookInfoManager:extractBookInfo(unreadable_file, nil)
      assert.is_false(unread_ok)
      open_stub:revert()
      os.remove(unreadable_file)
    end)

    it("should handle cover and metadata ignore, delete, and clean operations", function()
      BookInfoManager:createDB()
      BookInfoManager:openDbConnection()

      local dummy_file = "/tmp/test_cov_ignore.epub"
      local dir, fn = util.splitFilePathName(dummy_file)

      -- Insert record
      local dbrow = {
        directory = dir,
        filename = fn,
        filesize = 1000,
        filemtime = 1000,
        in_progress = 0,
        unsupported = nil,
        cover_fetched = "Y",
        has_meta = "Y",
        has_cover = "Y",
        cover_sizetag = "50x50",
        ignore_meta = nil,
        ignore_cover = nil,
        pages = 10,
        title = "Ignore Test",
        authors = "Author",
        series = nil,
        series_index = nil,
        language = "en",
        keywords = nil,
        description = "Test",
        cover_w = 50,
        cover_h = 50,
        cover_bb_type = 1,
        cover_bb_stride = 50,
        cover_bb_data = nil,
      }
      local BOOKINFO_COLS_SET = {
        "directory", "filename", "filesize", "filemtime",
        "in_progress", "unsupported", "cover_fetched",
        "has_meta", "has_cover", "cover_sizetag",
        "ignore_meta", "ignore_cover", "pages",
        "title", "authors", "series", "series_index",
        "language", "keywords", "description",
        "cover_w", "cover_h", "cover_bb_type", "cover_bb_stride", "cover_bb_data",
      }
      for num, col in ipairs(BOOKINFO_COLS_SET) do
        BookInfoManager.set_stmt:bind1(num, dbrow[col])
      end
      BookInfoManager.set_stmt:step()
      BookInfoManager.set_stmt:clearbind():reset()

      -- Ignore cover
      if BookInfoManager.ignoreCover then
        BookInfoManager:ignoreCover(dummy_file, true)
        assert.is_true(BookInfoManager:isCoverIgnored(dummy_file))
        BookInfoManager:ignoreCover(dummy_file, false)
        assert.is_false(BookInfoManager:isCoverIgnored(dummy_file))
      end

      -- Ignore meta
      if BookInfoManager.ignoreBookInfo then
        BookInfoManager:ignoreBookInfo(dummy_file, true)
        assert.is_true(BookInfoManager:isBookInfoIgnored(dummy_file))
        BookInfoManager:ignoreBookInfo(dummy_file, false)
        assert.is_false(BookInfoManager:isBookInfoIgnored(dummy_file))
      end

      -- Delete cover
      if BookInfoManager.deleteCover then
        BookInfoManager:deleteCover(dummy_file)
        local info = BookInfoManager:getBookInfo(dummy_file, false)
        assert.is_nil(info.has_cover)
      end
    end)
  end)
end)
