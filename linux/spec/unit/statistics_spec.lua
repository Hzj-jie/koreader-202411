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

  local function cleanup_db()
    os.remove(db_location)
    os.remove(db_location .. "-wal")
    os.remove(db_location .. "-shm")
    os.remove(db_location .. ".sync")
  end

  before_each(function()
    cleanup_db()
  end)

  after_each(function()
    cleanup_db()
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
      local now_t = os.date("*t")
      local now_ts = os.time()
      local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
      local start_today = now_ts - from_begin_day
      local days = stats:getDaysFromPeriod(start_today, start_today + 86400)
      assert.is_table(days)
      assert.is_same(1, #days)
    end)

    it("should retrieve books from period", function()
      local now_t = os.date("*t")
      local now_ts = os.time()
      local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
      local start_today = now_ts - from_begin_day
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

  describe("Defect verifications", function()
    it(
      "inserts page statistics into page_stat_data table without view modification error",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        local conn = SQ3.open(":memory:")
        stats:createDB(conn)
        stats.data = {
          title = "Different Book",
          authors = "Different Author",
        }
        stats.doc_md5 = "different_md5"
        local book_stats = {
          title = "Test Book",
          authors = "Test Author",
          notes = 0,
          highlights = 0,
          pages = 100,
          series = "Test Series",
          language = "en",
          file = "/dummy/test.epub",
          total_time_in_sec = 60,
          performance_in_pages = {
            [1000] = 5,
            [1030] = 6,
          },
        }

        local ok, res = pcall(function()
          return stats:addBookStatToDB(book_stats, conn)
        end)
        assert.is_true(ok, "addBookStatToDB should not throw an error")
        assert.is_true(res)

        local book_count =
          conn:rowexec("SELECT count(*) FROM book WHERE title = 'Test Book'")
        assert.are.equal(1, tonumber(book_count))

        local count = conn:rowexec("SELECT count(*) FROM page_stat_data")
        assert.are.equal(3, tonumber(count))

        conn:close()
      end
    )

    it(
      "selects yesterday when current time is earlier than day start hour",
      function()
        local CalendarView = require("plugins/statistics.koplugin/calendarview")
        local UIManager = require("ui/uimanager")
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.settings.calendar_day_start_hour = 23
        stats.settings.calendar_day_start_minute = 0

        -- 22:00 on 2026-10-10 (earlier than 23:00 day start hour)
        local fixed_time = os.time({
          year = 2026,
          month = 10,
          day = 10,
          hour = 22,
          min = 0,
          sec = 0,
        })
        local orig_time = os.time
        local orig_show = UIManager.show
        local captured_view

        finally(function()
          os.time = orig_time
          UIManager.show = orig_show
        end)

        os.time = function(t)
          if not t then
            return fixed_time
          end
          return orig_time(t)
        end

        UIManager.show = function(self, view)
          captured_view = view
        end

        local cal_view = CalendarView:new({
          ui = stats.ui,
          reader_statistics = stats,
        })

        cal_view:showCalendarDayView(stats)

        assert.is_not_nil(captured_view)
        local resolved_date = os.date("*t", captured_view.day_ts)
        assert.are.equal(
          9,
          resolved_date.day,
          "CalendarDayView day_ts should be for yesterday (day 9) when before day start hour"
        )
      end
    )
  end)

  it(
    "should use singular form when migrating 1 book in _checkInitDatabase",
    function()
      local UIManager = require("ui/uimanager")
      local ReadHistory = require("readhistory")
      local orig_show = UIManager.show
      local orig_close = UIManager.close
      local orig_forceRepaint = UIManager.forceRepaint
      local orig_hist = ReadHistory.hist

      local shown_texts = {}
      UIManager.show = function(self, widget)
        if widget and widget.text then
          table.insert(shown_texts, widget.text)
        end
      end
      UIManager.close = function() end
      UIManager.forceRepaint = function() end
      ReadHistory.hist = { { text = "/path/to/some_book.epub" } }

      finally(function()
        UIManager.show = orig_show
        UIManager.close = orig_close
        UIManager.forceRepaint = orig_forceRepaint
        ReadHistory.hist = orig_hist
        os.remove(db_location)
      end)

      local opts = helper_create_stats_opts()
      opts.ui.doc_props = nil
      local stats = ReaderStatistics:new(opts)
      stats.migrateToDB = function()
        return 1
      end

      stats:_checkInitDatabase()

      assert.is_true(#shown_texts >= 2)
      assert.are.equal(
        require("ffi/util").template(
          require("gettext").ngettext(
            "Conversion complete.\nImported one book to the database.\nTap to continue.",
            "Conversion complete.\nImported %1 books to the database.\nTap to continue.",
            1
          ),
          1
        ),
        shown_texts[#shown_texts]
      )
    end
  )

  it(
    "flushes volatile page stats to database before syncing in onSyncBookStats",
    function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      local conn = SQ3.open(db_location)
      conn:exec(
        "INSERT OR IGNORE INTO book (id, title, total_read_time) VALUES (1, 'Test Book', 0);"
      )
      conn:close()

      stats.is_doc_not_frozen = true
      stats.curr_page = 10
      stats.id_curr_book = 1
      stats.data = { pages = 200 }
      stats.settings.is_enabled = true
      stats.settings.sync_server = { type = "dropbox" }
      stats.page_stat = {
        [5] = { { os.time() - 30, 25 } },
        [10] = { { os.time(), 0 } },
      }

      local NetworkMgr = require("ui/network/manager")
      local BackgroundJobs = require("background_jobs")
      local orig_runWhenOnline = NetworkMgr.runWhenOnline
      local orig_insertKeyed = BackgroundJobs.insertKeyed
      finally(function()
        NetworkMgr.runWhenOnline = orig_runWhenOnline
        BackgroundJobs.insertKeyed = orig_insertKeyed
        os.remove(db_location)
        os.remove(DataStorage:getSettingsDir() .. "/statistics_sync/statistics.sqlite3")
        os.remove(DataStorage:getSettingsDir() .. "/statistics_sync/statistics.sqlite3.sync")
      end)

      NetworkMgr.runWhenOnline = function(_self_net, cb)
        cb()
        return true
      end
      BackgroundJobs.insertKeyed = function(job)
        job.callback({ result = false })
        return true
      end

      stats:onSyncBookStats()

      local conn_check = SQ3.open(db_location)
      local count = conn_check:rowexec(
        "SELECT count(*) FROM page_stat_data WHERE id_book = 1 AND page = 5 AND duration = 25"
      )
      conn_check:close()
      assert.are.equal(1, tonumber(count))
    end
  )

  describe("Background statistics cloud sync", function()
    local webdavapi = require("apps/cloudstorage/webdavapi")
    local NetworkMgr = require("ui/network/manager")
    local BackgroundJobs = require("background_jobs")
    local UIManager = require("ui/uimanager")
    local lfs = require("libs/libkoreader-lfs")
    local DataStorage = require("datastorage")
    local sync_dir = DataStorage:getSettingsDir() .. "/statistics_sync"
    local work_db_path = sync_dir .. "/statistics.sqlite3"

    before_each(function()
      os.remove(db_location)
      os.remove(db_location .. ".sync")
      os.remove(work_db_path)
      os.remove(work_db_path .. ".sync")
    end)

    it(
      "runs background sync with real SyncService, merges remote data and inflight local data, and updates stats",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        local conn = SQ3.open(db_location)
        conn:exec(
          "INSERT OR IGNORE INTO book (id, title, authors, md5, pages, total_read_time) VALUES (1, 'Local Book', 'Author', 'md5local', 100, 100);"
        )
        conn:exec(
          "INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages) VALUES (1, 1, 1000, 100, 100);"
        )
        conn:close()

        stats.is_doc_not_frozen = true
        stats.curr_page = 1
        stats.id_curr_book = 1
        stats.data = { pages = 100 }
        stats.settings.is_enabled = true
        stats.settings.sync_server = {
          type = "webdav",
          address = "http://example.com",
          url = "/stats",
          username = "user",
          password = "pwd",
        }

        local orig_download = webdavapi.downloadFile
        local orig_upload = webdavapi.uploadFile
        local orig_isConnected = NetworkMgr.isConnected
        local orig_isOnline = NetworkMgr.isOnline
        local orig_runWhenConnected = NetworkMgr.runWhenConnected
        local orig_runWhenOnline = NetworkMgr.runWhenOnline
        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_show = UIManager.show

        local captured_job = nil
        local shown_notifications = {}
        local shown_messages = {}
        local remote_db_file = nil

        finally(function()
          webdavapi.downloadFile = orig_download
          webdavapi.uploadFile = orig_upload
          NetworkMgr.isConnected = orig_isConnected
          NetworkMgr.isOnline = orig_isOnline
          NetworkMgr.runWhenConnected = orig_runWhenConnected
          NetworkMgr.runWhenOnline = orig_runWhenOnline
          BackgroundJobs.insertKeyed = orig_insertKeyed
          UIManager.show = orig_show
          os.remove(db_location)
          os.remove(db_location .. ".sync")
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
          if remote_db_file then
            os.remove(remote_db_file)
          end
        end)

        NetworkMgr.isConnected = function()
          return true
        end
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkMgr.runWhenConnected = function(_self_net, cb)
          cb()
          return true
        end
        NetworkMgr.runWhenOnline = function(_self_net, cb)
          cb()
          return true
        end

        webdavapi.downloadFile = function(
          _self_api,
          _path,
          _user,
          _pass,
          income_file_path
        )
          remote_db_file = income_file_path
          local conn_remote = SQ3.open(income_file_path)
          conn_remote:exec([[
            CREATE TABLE book (
              id INTEGER PRIMARY KEY,
              title TEXT,
              authors TEXT,
              notes INTEGER,
              last_open INTEGER,
              highlights INTEGER,
              pages INTEGER,
              series TEXT,
              language TEXT,
              md5 TEXT,
              total_read_time INTEGER,
              total_read_pages INTEGER
            );
            CREATE TABLE page_stat_data (
              id_book INTEGER,
              page INTEGER,
              start_time INTEGER,
              duration INTEGER,
              total_pages INTEGER
            );
            PRAGMA user_version = 20221111;
            INSERT INTO book (id, title, authors, md5, total_read_time) VALUES (2, 'Remote Book', 'Remote Author', 'md5remote', 50);
            INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages) VALUES (2, 1, 1500, 50, 100);
          ]])
          conn_remote:close()
          return 200, "etag123"
        end

        webdavapi.uploadFile = function()
          return 201
        end

        BackgroundJobs.insertKeyed = function(job)
          captured_job = job
          return true
        end

        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:_syncBookStats(false)
        assert.is_not_nil(captured_job)
        assert.are.equal("fork", captured_job.executable)

        -- While job is in flight, user turns a page and flushes it to db_location
        local conn_flight = SQ3.open(db_location)
        conn_flight:exec(
          "INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages) VALUES (1, 2, 2000, 80, 100);"
        )
        conn_flight:close()

        -- Run child action
        local action_res = captured_job.action()
        assert.are.equal(true, action_res)

        -- Run parent callback
        captured_job.callback({ result = action_res })

        -- Assert both remote row and in-flight local turn exist in db_location
        local conn_check = SQ3.open(db_location)
        local count_remote = conn_check:rowexec(
          "SELECT count(*) FROM book WHERE id = 2 AND title = 'Remote Book'"
        )
        local count_local_flight = conn_check:rowexec(
          "SELECT count(*) FROM page_stat_data WHERE id_book = 1 AND page = 2 AND duration = 80"
        )
        conn_check:close()
        assert.are.equal(1, tonumber(count_remote))
        assert.are.equal(1, tonumber(count_local_flight))

        -- Assert db_location .. ".sync" exists, work paths cleaned up
        assert.are.equal("file", lfs.attributes(db_location .. ".sync", "mode"))
        assert.is_nil(lfs.attributes(work_db_path, "mode"))
        assert.is_nil(lfs.attributes(work_db_path .. ".sync", "mode"))

        -- Assert totals were refreshed
        assert.are.equal(2, stats.book_read_pages)
        assert.are.equal(180, stats.book_read_time)
        assert.are.equal(90, stats.avg_time)

        assert.are.equal(
          require("gettext")("Syncing book statistics in the background"),
          shown_notifications[1]
        )
        assert.are.equal(
          require("gettext")("Successfully synchronized."),
          shown_notifications[2]
        )
        assert.are.equal(0, #shown_messages)
      end
    )

    it(
      "skips merge-back and sync file creation if sync_server changed or was deleted while in flight",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.is_doc_not_frozen = true
        stats.curr_page = 1
        stats.id_curr_book = 1
        stats.data = { pages = 100 }
        stats.settings.is_enabled = true
        stats.settings.sync_server = {
          type = "webdav",
          address = "http://example.com",
          url = "/stats",
          username = "user",
          password = "pwd",
        }

        local orig_download = webdavapi.downloadFile
        local orig_upload = webdavapi.uploadFile
        local orig_isConnected = NetworkMgr.isConnected
        local orig_isOnline = NetworkMgr.isOnline
        local orig_runWhenConnected = NetworkMgr.runWhenConnected
        local orig_runWhenOnline = NetworkMgr.runWhenOnline
        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_show = UIManager.show

        local captured_job = nil
        local shown_messages = {}
        local shown_notifications = {}

        finally(function()
          webdavapi.downloadFile = orig_download
          webdavapi.uploadFile = orig_upload
          NetworkMgr.isConnected = orig_isConnected
          NetworkMgr.isOnline = orig_isOnline
          NetworkMgr.runWhenConnected = orig_runWhenConnected
          NetworkMgr.runWhenOnline = orig_runWhenOnline
          BackgroundJobs.insertKeyed = orig_insertKeyed
          UIManager.show = orig_show
          os.remove(db_location)
          os.remove(db_location .. ".sync")
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
        end)

        NetworkMgr.isConnected = function()
          return true
        end
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkMgr.runWhenConnected = function(_self_net, cb)
          cb()
          return true
        end
        NetworkMgr.runWhenOnline = function(_self_net, cb)
          cb()
          return true
        end
        webdavapi.downloadFile = function(
          _self_api,
          _path,
          _user,
          _pass,
          income_file_path
        )
          local conn_inc = SQ3.open(income_file_path)
          conn_inc:exec([[
            CREATE TABLE book (
              id INTEGER PRIMARY KEY,
              title TEXT,
              authors TEXT,
              notes INTEGER,
              last_open INTEGER,
              highlights INTEGER,
              pages INTEGER,
              series TEXT,
              language TEXT,
              md5 TEXT,
              total_read_time INTEGER,
              total_read_pages INTEGER
            );
            CREATE TABLE page_stat_data (
              id_book INTEGER,
              page INTEGER,
              start_time INTEGER,
              duration INTEGER,
              total_pages INTEGER
            );
            PRAGMA user_version = 20221111;
          ]])
          conn_inc:close()
          return 200, "etag123"
        end
        webdavapi.uploadFile = function()
          return 201
        end
        BackgroundJobs.insertKeyed = function(job)
          captured_job = job
          return true
        end
        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:_syncBookStats(false)
        assert.is_not_nil(captured_job)

        local action_res = captured_job.action()
        assert.are.equal(true, action_res)

        -- Change sync server mid-flight
        stats.settings.sync_server = {
          type = "dropbox",
          url = "https://dropbox.com",
        }

        captured_job.callback({ result = action_res })

        -- db_location .. ".sync" must not exist
        assert.is_nil(lfs.attributes(db_location .. ".sync", "mode"))
        -- work paths cleaned up
        assert.is_nil(lfs.attributes(work_db_path, "mode"))
        assert.is_nil(lfs.attributes(work_db_path .. ".sync", "mode"))
        -- Error message shown
        assert.are.equal(
          require("gettext")("Syncing book statistics in the background"),
          shown_notifications[1]
        )
        assert.are.equal(
          require("gettext")("Failed to sync book statistics."),
          shown_notifications[#shown_notifications]
        )
        assert.are.equal(0, #shown_messages)
      end
    )

    it(
      "fails and avoids updating sync base if merge-back fails",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.is_doc_not_frozen = true
        stats.curr_page = 1
        stats.id_curr_book = 1
        stats.data = { pages = 100 }
        stats.settings.is_enabled = true
        stats.settings.sync_server = {
          type = "webdav",
          address = "http://example.com",
          url = "/stats",
        }

        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_show = UIManager.show
        local captured_job = nil
        local shown_messages = {}
        local shown_notifications = {}

        finally(function()
          BackgroundJobs.insertKeyed = orig_insertKeyed
          UIManager.show = orig_show
          if captured_job and captured_job.callback then
            pcall(captured_job.callback, { result = false })
          end
          os.remove(db_location)
          os.remove(db_location .. ".sync")
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
        end)

        BackgroundJobs.insertKeyed = function(job)
          captured_job = job
          return true
        end
        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:_syncBookStats(false)
        assert.is_not_nil(captured_job)

        -- Prepare work_db_path .. ".sync"
        require("ffi/util").copyFile(work_db_path, work_db_path .. ".sync")

        -- Delete db_location so merge-back ReaderStatistics.onSync fails
        os.remove(db_location)

        -- Trigger callback with job.result == true
        captured_job.callback({ result = true })

        -- db_location .. ".sync" must NOT exist because merge-back failed
        assert.is_nil(lfs.attributes(db_location .. ".sync", "mode"))

        -- Error notification should be shown
        assert.are.equal(
          require("gettext")("Failed to sync book statistics."),
          shown_notifications[#shown_notifications]
        )
        assert.are.equal(0, #shown_messages)
      end
    )

    it(
      "handles non-boolean CommandRunner error sentinels safely without crashing",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.settings.is_enabled = true
        stats.settings.sync_server =
          { type = "webdav", address = "http://example.com" }

        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_show = UIManager.show
        local captured_job = nil
        local shown_messages = {}
        local shown_notifications = {}

        finally(function()
          BackgroundJobs.insertKeyed = orig_insertKeyed
          UIManager.show = orig_show
          os.remove(db_location)
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
        end)

        BackgroundJobs.insertKeyed = function(job)
          captured_job = job
          return true
        end
        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:_syncBookStats(false)
        assert.is_not_nil(captured_job)

        -- Test sentinel 222 (e.g. CommandRunner killed/aborted)
        captured_job.callback({ result = 222 })
        assert.are.equal(
          require("gettext")("Failed to sync book statistics."),
          shown_notifications[#shown_notifications]
        )
        assert.are.equal(0, #shown_messages)

        -- Test sentinel 255 (e.g. CommandRunner error exit)
        stats:_syncBookStats(false)
        captured_job.callback({ result = 255 })
        assert.are.equal(
          require("gettext")("Failed to sync book statistics."),
          shown_notifications[#shown_notifications]
        )
        assert.are.equal(0, #shown_messages)
      end
    )

    it(
      "prevents concurrent sync when already in progress and resets when callback finishes",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.settings.is_enabled = true
        stats.settings.sync_server =
          { type = "webdav", address = "http://example.com" }

        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_isConnected = NetworkMgr.isConnected
        local orig_isOnline = NetworkMgr.isOnline
        local orig_runWhenConnected = NetworkMgr.runWhenConnected
        local orig_runWhenOnline = NetworkMgr.runWhenOnline
        local orig_show = UIManager.show
        local captured_job = nil
        local count_jobs = 0
        local shown_messages = {}
        local shown_notifications = {}

        finally(function()
          BackgroundJobs.insertKeyed = orig_insertKeyed
          NetworkMgr.isConnected = orig_isConnected
          NetworkMgr.isOnline = orig_isOnline
          NetworkMgr.runWhenConnected = orig_runWhenConnected
          NetworkMgr.runWhenOnline = orig_runWhenOnline
          UIManager.show = orig_show
          if captured_job and captured_job.callback then
            pcall(captured_job.callback, { result = false })
          end
          os.remove(db_location)
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
        end)

        NetworkMgr.isConnected = function()
          return true
        end
        NetworkMgr.isOnline = function()
          return true
        end
        NetworkMgr.runWhenConnected = function(_self_net, cb)
          cb()
          return true
        end
        NetworkMgr.runWhenOnline = function(_self_net, cb)
          cb()
          return true
        end
        BackgroundJobs.insertKeyed = function(job)
          count_jobs = count_jobs + 1
          captured_job = job
          return true
        end
        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:_syncBookStats(false)
        assert.are.equal(1, count_jobs)

        -- Attempt second sync while first is in flight
        stats:onSyncBookStats()
        assert.are.equal(1, count_jobs)
        assert.are.equal(
          require("gettext")("Sync is already in progress."),
          shown_notifications[#shown_notifications]
        )
        assert.are.equal(0, #shown_messages)

        -- Finish first job
        captured_job.callback({ result = false })

        -- Subsequent sync should now be accepted
        stats:onSyncBookStats()
        assert.are.equal(2, count_jobs)
        captured_job.callback({ result = false })
      end
    )

    it(
      "does not show start notification for silent auto sync or when job insertion fails",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.settings.is_enabled = true
        stats.settings.sync_server =
          { type = "webdav", address = "http://example.com" }

        local orig_insertKeyed = BackgroundJobs.insertKeyed
        local orig_show = UIManager.show
        local shown_notifications = {}
        local shown_messages = {}

        finally(function()
          BackgroundJobs.insertKeyed = orig_insertKeyed
          UIManager.show = orig_show
          os.remove(db_location)
          os.remove(work_db_path)
          os.remove(work_db_path .. ".sync")
        end)

        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        -- Case 1: insertKeyed returns false
        BackgroundJobs.insertKeyed = function()
          return false
        end
        stats:_syncBookStats(false)
        assert.are.equal(0, #shown_notifications)
        assert.are.equal(0, #shown_messages)

        -- Case 2: silent sync (auto sync)
        BackgroundJobs.insertKeyed = function(job)
          job.callback({ result = true })
          return true
        end
        stats:_syncBookStats(true)
        assert.are.equal(0, #shown_notifications)
        assert.are.equal(0, #shown_messages)
      end
    )

    it(
      "does not show InfoMessage before network gate in onSyncBookStats",
      function()
        local stats = ReaderStatistics:new(helper_create_stats_opts())
        stats.settings.is_enabled = true
        stats.settings.sync_server =
          { type = "webdav", address = "http://example.com" }

        local orig_runWhenConnected = NetworkMgr.runWhenConnected
        local orig_show = UIManager.show
        local shown_notifications = {}
        local shown_messages = {}

        finally(function()
          NetworkMgr.runWhenConnected = orig_runWhenConnected
          UIManager.show = orig_show
        end)

        NetworkMgr.runWhenConnected = function()
          -- do not invoke callback immediately (simulates waiting for network)
          return true
        end

        UIManager.show = function(_self_ui, widget)
          if widget and widget.toast then
            table.insert(shown_notifications, widget.text)
          elseif widget and widget.text then
            table.insert(shown_messages, widget.text)
          end
        end

        stats:onSyncBookStats()
        assert.are.equal(0, #shown_messages)
        assert.are.equal(0, #shown_notifications)
      end
    )
  end)

  describe("Auto sync when idle", function()
    it("adds auto sync toggle to settings menu", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      stats.settings.is_enabled = true
      stats.settings.sync_server = { type = "dropbox" }

      local menu_items = {}
      stats:addToMainMenu(menu_items)
      assert.is_table(menu_items.statistics)
      local settings_item = menu_items.statistics.sub_item_table[2]
      assert.are.equal(require("gettext")("Settings"), settings_item.text)

      local auto_sync_item = nil
      for _, item in ipairs(settings_item.sub_item_table) do
        if item.text == require("gettext")("Auto sync when idle") then
          auto_sync_item = item
          break
        end
      end
      assert.is_not_nil(auto_sync_item)
      assert.is_false(auto_sync_item.checked_func())
      assert.is_true(auto_sync_item.enabled_func())

      auto_sync_item.callback()
      assert.is_true(stats.settings.auto_sync)
      assert.is_true(auto_sync_item.checked_func())
    end)

    it("gates onTimesChange_1M on auto_sync setting and canSync", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      local sync_called = false
      stats._syncBookStats = function()
        sync_called = true
      end

      -- Disabled when auto_sync is false
      stats.settings.is_enabled = true
      stats.settings.sync_server = { type = "dropbox" }
      stats.settings.auto_sync = false
      stats:onTimesChange_1M()
      assert.is_false(sync_called)

      -- Disabled when canSync is false
      stats.settings.auto_sync = true
      stats.settings.sync_server = nil
      stats:onTimesChange_1M()
      assert.is_false(sync_called)
    end)

    it("gates onTimesChange_1M on 5-minute idle time threshold", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      local sync_called = false
      stats._syncBookStats = function()
        sync_called = true
      end

      stats.settings.is_enabled = true
      stats.settings.sync_server = { type = "dropbox" }
      stats.settings.auto_sync = true

      local UIManager = require("ui/uimanager")
      local time = require("ui/time")
      local orig_timeSince = UIManager.timeSinceLastUserAction
      finally(function()
        UIManager.timeSinceLastUserAction = orig_timeSince
      end)

      -- Less than 5 minutes idle
      UIManager.timeSinceLastUserAction = function()
        return time.s(299)
      end
      stats:onTimesChange_1M()
      assert.is_false(sync_called)
    end)

    it("triggers silent auto sync when all conditions are met and avoids duplicate runs in same idle period", function()
      local stats = ReaderStatistics:new(helper_create_stats_opts())
      local sync_silent_arg = nil
      stats._syncBookStats = function(_self_inst, is_silent)
        sync_silent_arg = is_silent
      end

      stats.settings.is_enabled = true
      stats.settings.sync_server = { type = "dropbox" }
      stats.settings.auto_sync = true

      local UIManager = require("ui/uimanager")
      local NetworkMgr = require("ui/network/manager")
      local SyncService = require("frontend/apps/cloudstorage/syncservice")
      local time = require("ui/time")

      local orig_timeSince = UIManager.timeSinceLastUserAction
      local orig_lastAction = UIManager.lastUserActionTime
      local orig_isOnline = NetworkMgr.isOnline
      local orig_getLastSync = SyncService.getLastSyncTime

      finally(function()
        UIManager.timeSinceLastUserAction = orig_timeSince
        UIManager.lastUserActionTime = orig_lastAction
        NetworkMgr.isOnline = orig_isOnline
        SyncService.getLastSyncTime = orig_getLastSync
      end)

      UIManager.timeSinceLastUserAction = function()
        return time.s(350)
      end
      UIManager.lastUserActionTime = function()
        return 12345
      end
      NetworkMgr.isOnline = function()
        return true
      end
      SyncService.getLastSyncTime = function()
        return os.time() - 3601
      end

      stats:onTimesChange_1M()
      assert.are.equal(true, sync_silent_arg)
      assert.are.equal(12345, stats.last_auto_sync_action_time)

      -- Second trigger in the same idle period should be blocked by last_auto_sync_action_time
      sync_silent_arg = nil
      stats:onTimesChange_1M()
      assert.is_nil(sync_silent_arg)

      -- If last_sync is recent (< 1 hour), should also block
      UIManager.lastUserActionTime = function()
        return 12346 -- new action
      end
      SyncService.getLastSyncTime = function()
        return os.time() - 100 -- recently synced
      end
      stats:onTimesChange_1M()
      assert.is_nil(sync_silent_arg)
    end)
  end)
end)
