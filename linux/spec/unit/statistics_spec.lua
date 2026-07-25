describe("Statistics plugin", function()
  local ReaderStatistics, G_reader_settings, DataStorage, SQ3, db_location

  local function helper_create_stats_opts(opts)
    opts = opts or {}
    return {
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
        getCurrentPage = function()
          return opts.curr_page or 1
        end,
        doc_settings = opts.doc_settings or {
          readTableRef = function(_, key, default)
            if key == "summary" then
              return opts.summary or { status = "complete" }
            end
            return default
          end,
          read = function(_, key)
            if key == "partial_md5_checksum" then
              return opts.doc_md5 or "dummy_md5"
            end
            return nil
          end,
        },
        doc_props = opts.doc_props or {
          display_title = "Test Book",
          authors = "Test Author",
          language = "en",
        },
        annotation = {
          getNumberOfHighlightsAndNotes = function()
            return 2, 1
          end,
        },
        view = {
          state = { page = 1 },
        },
      },
      document = opts.document or {
        file = "/books/test.epub",
        getPageCount = function()
          return opts.page_count or 200
        end,
        hasHiddenFlows = function()
          return false
        end,
      },
    }
  end

  setup(function()
    require("commonrequire")
    G_reader_settings = require("luasettings"):open("reader")
    DataStorage = require("datastorage")
    SQ3 = require("lua-ljsqlite3/init")
    db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    ReaderStatistics = require("plugins/statistics.koplugin/main")
  end)

  before_each(function()
    os.remove(db_location)
  end)

  after_each(function()
    os.remove(db_location)
  end)

  it("should initialize ReaderStatistics class", function()
    assert.is_table(ReaderStatistics)
    assert.is_function(ReaderStatistics.new)
  end)

  it("should instantiate ReaderStatistics with ui mockup", function()
    local stats = ReaderStatistics:new(helper_create_stats_opts())
    assert.is_table(stats)
    assert.is_table(stats.settings)
    assert.is_true(stats.settings.is_enabled)
  end)

  describe("Status and Settings Handlers", function()
    it("should check isEnabled correctly", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.settings.is_enabled = true
      stats.is_doc = true
      assert.is_true(stats:isEnabled())

      stats.is_doc = false
      assert.is_false(stats:isEnabled())

      stats.settings.is_enabled = false
      stats.is_doc = true
      assert.is_false(stats:isEnabled())
    end)

    it("should check isEnabledAndNotFrozen correctly", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.settings.is_enabled = true
      stats.is_doc_not_frozen = true
      assert.is_true(stats:isEnabledAndNotFrozen())

      stats.is_doc_not_frozen = false
      assert.is_false(stats:isEnabledAndNotFrozen())
    end)

    it("should update frozen status based on document summary", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts({
        summary = { status = "reading" },
      }))
      stats.is_doc = true
      stats.settings.freeze_finished_books = true
      stats:_updateFrozen()
      assert.is_true(stats.is_doc_not_finished)
      assert.is_true(stats.is_doc_not_frozen)

      stats.ui.doc_settings = {
        readTableRef = function(_, key)
          if key == "summary" then
            return { status = "complete" }
          end
        end,
      }
      stats:_updateFrozen()
      assert.is_false(stats.is_doc_not_finished)
      assert.is_false(stats.is_doc_not_frozen)
    end)

    it("should toggle statistics state", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.settings.is_enabled = true
      stats:onToggleStatistics(true)
      assert.is_false(stats.settings.is_enabled)

      stats:onToggleStatistics(true)
      assert.is_true(stats.settings.is_enabled)
    end)
  end)

  describe("Volatile Stats and Session Management", function()
    it("should reset volatile stats without timestamp", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.pageturn_count = 5
      stats.mem_read_time = 100
      stats.mem_read_pages = 10
      stats:resetVolatileStats()
      assert.is_same(0, stats.pageturn_count)
      assert.is_same(0, stats.mem_read_time)
      assert.is_same(0, stats.mem_read_pages)
      assert.is_same({}, stats.page_stat)
    end)

    it("should seed volatile stats when now_ts is provided", function()
      local stats =
        ReaderStatistics:new(helper_create_stats_opts({ curr_page = 3 }))
      stats.curr_page = 3
      local now_ts = 1600000000
      stats:resetVolatileStats(now_ts)
      assert.is_same({ { now_ts, 0 } }, stats.page_stat[3])
    end)

    it("should preserve current session period", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.start_current_period = 123456789
      stats:onPreserveCurrentSession()
      assert.is_same(123456789, ReaderStatistics.preserved_start_current_period)
    end)
  end)

  describe("Database Creation and Schema Upgrades", function()
    it("should create database schema and set user_version", function()
      local conn = SQ3.open(":memory:")
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats:createDB(conn)

      local version = conn:rowexec("PRAGMA user_version;")
      assert.is_same(20221111, tonumber(version))

      local has_book = conn:rowexec(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='book';"
      )
      assert.is_same("book", has_book)

      local has_page_stat_data = conn:rowexec(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='page_stat_data';"
      )
      assert.is_same("page_stat_data", has_page_stat_data)

      conn:close()
    end)

    it("should upgrade DB schema to 20221111 and deduplicate books", function()
      local conn = SQ3.open(":memory:")
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      -- Setup base tables
      conn:exec([[
        CREATE TABLE book (
          id integer PRIMARY KEY autoincrement,
          title text,
          authors text,
          notes integer,
          last_open integer,
          highlights integer,
          pages integer,
          series text,
          language text,
          md5 text,
          total_read_time integer,
          total_read_pages integer
        );
        CREATE TABLE page_stat_data (
          id_book integer,
          page integer,
          start_time integer,
          duration integer,
          total_pages integer
        );
        CREATE VIEW page_stat AS SELECT id_book, page, start_time, duration FROM page_stat_data;
      ]])

      -- Insert duplicate books
      conn:exec(
        "INSERT INTO book (id, title, authors, md5) VALUES (1, 'Book A', 'Author A', 'md5_1');"
      )
      conn:exec(
        "INSERT INTO book (id, title, authors, md5) VALUES (2, 'Book A', 'Author A', 'md5_1');"
      )
      conn:exec("INSERT INTO page_stat_data VALUES (1, 1, 1000, 30, 100);")
      conn:exec("INSERT INTO page_stat_data VALUES (2, 2, 1030, 40, 100);")

      stats:upgradeDBto20221111(conn)

      local version = conn:rowexec("PRAGMA user_version;")
      assert.is_same(20221111, tonumber(version))

      local book_count = conn:rowexec("SELECT count(*) FROM book;")
      assert.is_same(1, tonumber(book_count))

      conn:close()
    end)
  end)

  describe("Book & Period Statistics Calculations", function()
    local stats, conn

    before_each(function()
      stats = ReaderStatistics:new(helper_create_stats_opts())
      conn = SQ3.open(db_location)

      local now_t = os.date("*t")
      local now_ts = os.time()
      local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
      local start_today = now_ts - from_begin_day

      -- Insert test book record with last_open set
      conn:exec(string.format(
        [[
        INSERT INTO book (id, title, authors, notes, last_open, highlights, pages, md5, total_read_time, total_read_pages)
        VALUES (1, 'Test Book', 'Test Author', 1, %d, 2, 200, 'test_md5', 120, 4);
      ]],
        now_ts
      ))

      -- Insert test page statistics
      conn:exec(string.format(
        [[
        INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages)
        VALUES (1, 1, %d, 30, 200);
        INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages)
        VALUES (1, 2, %d, 40, 200);
        INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages)
        VALUES (1, 3, %d, 50, 200);
      ]],
        start_today + 100,
        start_today + 200,
        start_today + 300
      ))

      stats.id_curr_book = 1
      stats.start_current_period = start_today
    end)

    after_each(function()
      if conn then
        conn:close()
      end
    end)

    it("should calculate page and time total stats for a book", function()
      local pages, duration = stats:getPageTimeTotalStats(1)
      assert.is_same(3, pages)
      assert.is_same(120, duration)

      local empty_pages, empty_duration = stats:getPageTimeTotalStats(999)
      assert.is_same(0, empty_pages)
      assert.is_same(0, empty_duration)
    end)

    it("should calculate today book stats", function()
      local duration, pages = stats:getTodayBookStats()
      assert.is_same(120, duration)
      assert.is_same(3, pages)
    end)

    it("should calculate current period book stats", function()
      local duration, pages = stats:getCurrentBookStats()
      assert.is_same(120, duration)
      assert.is_same(3, pages)
    end)

    it("should get status for book status widget", function()
      local status = stats:getStatsBookStatus(1, true)
      assert.is_table(status)
      assert.is_same(1, status.days)
      assert.is_same(120, status.time)
      assert.is_same(3, status.pages)

      local disabled_status = stats:getStatsBookStatus(1, false)
      assert.is_same({}, disabled_status)

      local nil_status = stats:getStatsBookStatus(nil, true)
      assert.is_same({}, nil_status)
    end)

    it("should retrieve days from period", function()
      local now_ts = os.time()
      local start_today = now_ts - (now_ts % 86400)
      local days = stats:getDaysFromPeriod(start_today, start_today + 86400)
      assert.is_table(days)
      assert.is_same(1, #days)
    end)

    it("should retrieve books from period", function()
      local now_ts = os.time()
      local start_today = now_ts - (now_ts % 86400)
      local books = stats:getBooksFromPeriod(start_today, start_today + 86400)
      assert.is_table(books)
      assert.is_same(1, #books)
      assert.is_same("Test Book", books[1][1])
      assert.is_same(120, books[1].duration)
      assert.is_same(1, books[1].book_id)
    end)

    it("should retrieve reading progress stats", function()
      local progress = stats:getReadingProgressStats(1)
      assert.is_table(progress)
      assert.is_same(1, #progress)
      assert.is_same(3, progress[1][1])
      assert.is_same(120, progress[1][2])
    end)

    it("should retrieve dates for a specific book", function()
      local dates = stats:getDatesForBook(1)
      assert.is_table(dates)
      assert.is_same(1, #dates)
    end)

    it("should retrieve total stats across all books", function()
      local total_str, total_stats = stats:getTotalStats()
      assert.is_string(total_str)
      assert.is_table(total_stats)
      assert.is_same(1, #total_stats)
      assert.is_same("Test Book", total_stats[1][1])
    end)

    it("should retrieve stats for a specific book", function()
      local book_stat = stats:getBookStat(1)
      assert.is_table(book_stat)
      assert.is_same("Test Book", book_stat[1][2])
      assert.is_same("Test Author", book_stat[2][2])
    end)

    it("should delete book and its page statistics", function()
      stats:deleteBook(1)
      local book_count = conn:rowexec("SELECT count(*) FROM book WHERE id = 1;")
      assert.is_same(0, tonumber(book_count))
      local page_stat_count =
        conn:rowexec("SELECT count(*) FROM page_stat_data WHERE id_book = 1;")
      assert.is_same(0, tonumber(page_stat_count))
    end)

    it("should delete books by total duration threshold", function()
      -- Insert a non-current book (id 2) with total_read_time = 120 (2 mins)
      conn:exec(string.format(
        [[
        INSERT INTO book (id, title, authors, notes, last_open, highlights, pages, md5, total_read_time, total_read_pages)
        VALUES (2, 'Other Book', 'Other Author', 0, %d, 0, 100, 'other_md5', 120, 1);
      ]],
        os.time()
      ))

      local ConfirmBox = require("ui/widget/confirmbox")
      local orig_new = ConfirmBox.new
      ConfirmBox.new = function(self, args)
        if args and args.ok_callback then
          args.ok_callback()
        end
        return orig_new(self, args)
      end

      -- Threshold 5 mins should delete non-current book 2
      stats:deleteBooksByTotalDuration(5)

      ConfirmBox.new = orig_new

      local book2_count =
        conn:rowexec("SELECT count(*) FROM book WHERE id = 2;")
      assert.is_same(0, tonumber(book2_count))
    end)
  end)
end)
