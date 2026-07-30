describe("ReaderStatistics plugin main spec", function()
  local DataStorage, Device, Dispatcher, ReaderStatistics, UIManager
  local SQ3
  local db_location

  setup(function()
    require("commonrequire")
    DataStorage = require("datastorage")
    SQ3 = require("lua-ljsqlite3/init")
    db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
  end)

  before_each(function()
    Device = require("device")
    UIManager = require("ui/uimanager")
    Dispatcher = require("dispatcher")

    stub(Device, "hasKeys")
    stub(Device, "isTouchDevice")
    stub(Device, "canUseWAL")
    stub(UIManager, "show")
    stub(UIManager, "close")
    stub(UIManager, "broadcastEvent")
    stub(UIManager, "tickAfterNext")
    stub(UIManager, "nextTick")
    stub(Dispatcher, "registerAction")

    Device.hasKeys.returns(true)
    Device.isTouchDevice.returns(true)
    Device.canUseWAL.returns(false)

    -- Clean up DB and settings before each test
    os.remove(db_location)
    G_reader_settings:delete("statistics")

    package.loaded["plugins/statistics.koplugin/main"] = nil
    ReaderStatistics = require("plugins/statistics.koplugin/main")
  end)

  after_each(function()
    Device.hasKeys:revert()
    Device.isTouchDevice:revert()
    Device.canUseWAL:revert()
    UIManager.show:revert()
    UIManager.close:revert()
    UIManager.broadcastEvent:revert()
    UIManager.tickAfterNext:revert()
    UIManager.nextTick:revert()
    Dispatcher.registerAction:revert()

    os.remove(db_location)
    G_reader_settings:delete("statistics")
  end)

  local function createMockDoc()
    return {
      file = "/tmp/test_book.epub",
      getPageCount = function()
        return 100
      end,
      hasHiddenFlows = function()
        return false
      end,
    }
  end

  local function createMockUI()
    return {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      doc_props = {
        display_title = "Test Book",
        authors = "Test Author",
        language = "en",
        series = "Test Series",
        series_index = "1",
      },
      doc_settings = {
        read = function(self, key)
          if key == "partial_md5_checksum" then
            return "12345678901234567890123456789012"
          end
        end,
        readTableRef = function(self, key, default)
          if key == "stats" then
            return default or { performance_in_pages = {} }
          elseif key == "summary" then
            return { status = "reading" }
          end
          return default or {}
        end,
      },
      annotation = {
        getNumberOfHighlightsAndNotes = function()
          return 5, 2
        end,
      },
      getCurrentPage = function()
        return 10
      end,
      view = {
        state = { page = 10 },
      },
    }
  end

  local function createInstance(opts)
    opts = opts or {}
    local ui = opts.ui or createMockUI()
    local doc = opts.document or createMockDoc()
    return ReaderStatistics:new({
      ui = ui,
      document = doc,
    })
  end

  it("should ignore initialization for picture documents", function()
    local stats = ReaderStatistics:new({
      ui = createMockUI(),
      document = { is_pic = true },
    })
    assert.is_nil(stats.is_doc)
  end)

  it("should initialize instance and DB correctly when doc is ready", function()
    local stats = createInstance()
    assert.is_true(stats.is_doc)
    assert.is_true(stats.data_initialized)
    assert.are.equal("Test Book", stats.data.title)
    assert.are.equal("Test Author", stats.data.authors)
    assert.are.equal("en", stats.data.language)
    assert.are.equal("Test Series #1", stats.data.series)
    assert.are.equal(100, stats.data.pages)
    assert.are.equal(5, stats.data.highlights)
    assert.are.equal(2, stats.data.notes)
    assert.is_number(stats.id_curr_book)
  end)

  it("should register dispatcher actions", function()
    local stats = createInstance()
    stats:onDispatcherRegisterActions()
    assert.stub(Dispatcher.registerAction).was_called_with(
      match.ref(Dispatcher),
      "toggle_statistics",
      match.is_table()
    )
    assert.stub(Dispatcher.registerAction).was_called_with(
      match.ref(Dispatcher),
      "stats_calendar_view",
      match.is_table()
    )
    assert.stub(Dispatcher.registerAction).was_called_with(
      match.ref(Dispatcher),
      "stats_calendar_day_view",
      match.is_table()
    )
    assert.stub(Dispatcher.registerAction).was_called_with(
      match.ref(Dispatcher),
      "stats_sync",
      match.is_table()
    )
    assert.stub(Dispatcher.registerAction).was_called_with(
      match.ref(Dispatcher),
      "book_statistics",
      match.is_table()
    )
  end)

  it("should return enabled and frozen statuses accurately", function()
    local stats = createInstance()
    assert.is_true(stats:isEnabled())
    assert.is_true(stats:isEnabledAndNotFrozen())

    stats.settings.is_enabled = false
    assert.is_false(stats:isEnabled())
    assert.is_false(stats:isEnabledAndNotFrozen())

    stats.settings.is_enabled = true
    stats.settings.freeze_finished_books = true
    stats.ui.doc_settings.readTableRef = function(self, key)
      if key == "summary" then
        return { status = "complete" }
      end
      return {}
    end
    stats:_updateFrozen()
    assert.is_true(stats:isEnabled())
    assert.is_false(stats:isEnabledAndNotFrozen())
  end)

  it("should create DB schema on a new connection", function()
    local test_db = DataStorage:getSettingsDir() .. "/test_schema.sqlite3"
    os.remove(test_db)
    local conn = SQ3.open(test_db)

    ReaderStatistics:createDB(conn)
    local row = conn:rowexec("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='book';")
    assert.are.equal(1, tonumber(row))

    local version = tonumber(conn:rowexec("PRAGMA user_version;"))
    assert.are.equal(20221111, version)
    conn:close()
    os.remove(test_db)
  end)

  it("should handle DB schema upgrade routines from older versions", function()
    local test_db = DataStorage:getSettingsDir() .. "/test_upgrade.sqlite3"
    os.remove(test_db)
    local conn = SQ3.open(test_db)

    -- Set up old schema prior to 20201010
    conn:exec([[
      CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT, authors TEXT, md5 TEXT, pages INTEGER, total_read_pages INTEGER, total_read_time INTEGER);
      CREATE TABLE page_stat (id_book INTEGER, page INTEGER, period INTEGER, start_time INTEGER);
    ]])

    ReaderStatistics:upgradeDBto20201010(conn)
    local v1 = tonumber(conn:rowexec("PRAGMA user_version;"))
    assert.are.equal(20201010, v1)

    ReaderStatistics:upgradeDBto20201022(conn)
    local v2 = tonumber(conn:rowexec("PRAGMA user_version;"))
    assert.are.equal(20201022, v2)

    ReaderStatistics:upgradeDBto20221111(conn)
    local v3 = tonumber(conn:rowexec("PRAGMA user_version;"))
    assert.are.equal(20221111, v3)

    conn:close()
    os.remove(test_db)
  end)

  it("should handle page updates and calculate durations correctly", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 10, 0 } }

    -- Page update within valid bounds (10s)
    stats:onPageUpdate(2)
    assert.are.equal(2, stats.curr_page)
    assert.are.equal(10, stats.mem_read_time)
    assert.are.equal(1, stats.mem_read_pages)

    -- Page update exceeding max_sec (default 120s)
    stats.page_stat[2] = { { os.time() - 300, 0 } }
    stats:onPageUpdate(3)
    assert.are.equal(3, stats.curr_page)
    assert.are.equal(10 + stats.settings.max_sec, stats.mem_read_time)

    -- On closing document (pageno = false)
    stats.page_stat[3] = { { os.time() - 5, 0 } }
    stats:onPageUpdate(false)
    assert.are.equal(3, stats.curr_page)
  end)

  it("should handle page turn flush trigger after max pageturns", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 10, 0 } }

    stats.pageturn_count = 49
    stats:onPageUpdate(2)
    assert.are.equal(0, stats.pageturn_count)
    assert.stub(UIManager.tickAfterNext).was_called()
  end)

  it("should handle position updates", function()
    local stats = createInstance()
    stub(stats, "onPageUpdate")
    stats.curr_page = 1

    stats:onPosUpdate(nil, 1)
    assert.stub(stats.onPageUpdate).was_not_called()

    stats:onPosUpdate(nil, 2)
    assert.stub(stats.onPageUpdate).was_called_with(match.ref(stats), 2)
    stats.onPageUpdate:revert()
  end)

  it("should handle pause, resume, suspend and save events", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 20, 0 } }

    stats:onReadingPaused()
    assert.is_number(stats._reading_paused_ts)

    -- Updating page while paused shouldn't change duration, only record requested page
    stats:onPageUpdate(2)
    assert.are.equal(1, stats.curr_page)
    assert.are.equal(2, stats._reading_paused_curr_page)

    stats:onReadingResumed()
    assert.is_nil(stats._reading_paused_ts)
    assert.are.equal(2, stats.curr_page)

    -- Suspend & Resume
    stats:onSuspend()
    stats:onResume()
    assert.is_nil(stats._reading_paused_ts)

    -- Save settings & Close document
    stats:onSaveSettings()
    stats:onCloseDocument()

    -- Annotations modified
    stats:onAnnotationsModified({ nb_highlights_added = 2, nb_notes_added = 1 })
    assert.are.equal(7, stats.data.highlights)
    assert.are.equal(3, stats.data.notes)
  end)

  it("should update metadata on onBookMetadataChanged", function()
    local stats = createInstance()

    stats:onBookMetadataChanged({
      filepath = stats.document.file,
      metadata_key_updated = "title",
      doc_props = { display_title = "New Title" },
    })
    assert.are.equal("New Title", stats.data.title)

    stats:onBookMetadataChanged({
      filepath = stats.document.file,
      metadata_key_updated = "authors",
      doc_props = { authors = "New Author" },
    })
    assert.are.equal("New Author", stats.data.authors)

    stats:onBookMetadataChanged({
      filepath = stats.document.file,
      metadata_key_updated = "language",
      doc_props = { language = "fr" },
    })
    assert.are.equal("fr", stats.data.language)

    stats:onBookMetadataChanged({
      filepath = stats.document.file,
      metadata_key_updated = "series",
      doc_props = { series = "New Series", series_index = "2" },
    })
    assert.are.equal("New Series #2", stats.data.series)
  end)

  it("should populate main menu items correctly and trigger callbacks", function()
    local stats = createInstance()
    local menu_items = {}
    stats:addToMainMenu(menu_items)

    assert.is_table(menu_items.statistics)
    assert.are.equal("Reading statistics", menu_items.statistics.text)
    local sub = menu_items.statistics.sub_item_table
    assert.is_table(sub)
    assert.is_true(#sub > 0)

    -- Test sub-item callbacks and checked functions
    local enabled_item = sub[1]
    assert.is_true(enabled_item.checked_func())
    enabled_item.callback()
    assert.is_false(stats.settings.is_enabled)
    enabled_item.callback()
    assert.is_true(stats.settings.is_enabled)

    -- Settings sub-items
    local settings_sub = sub[2].sub_item_table
    assert.is_table(settings_sub)

    local dummy_menu = { updateItems = spy.new(function() end) }

    -- Read page duration limits
    local duration_item = settings_sub[1]
    assert.is_string(duration_item.text_func())
    duration_item.callback(dummy_menu)
    assert.stub(UIManager.show).was_called()

    -- Freeze finished books
    local freeze_item = settings_sub[2]
    assert.is_false(freeze_item.checked_func())
    freeze_item.callback()
    assert.is_true(stats.settings.freeze_finished_books)
    assert.is_true(freeze_item.checked_func())

    -- Calendar week start day
    local calendar_start_item = settings_sub[3]
    assert.is_string(calendar_start_item.text_func())
    local days_sub = calendar_start_item.sub_item_table
    assert.is_table(days_sub)
    days_sub[1].callback()
    assert.are.equal(6, stats.settings.calendar_start_day_of_week)
    assert.is_true(days_sub[1].checked_func())

    -- Books per calendar day
    local books_per_day_item = settings_sub[4]
    assert.is_string(books_per_day_item.text_func())
    books_per_day_item.callback(dummy_menu)

    -- Hourly histogram
    local histo_item = settings_sub[5]
    assert.is_true(histo_item.checked_func())
    histo_item.callback()
    assert.is_false(stats.settings.calendar_show_histogram)

    -- Browse future months
    local future_item = settings_sub[6]
    assert.is_false(future_item.checked_func())
    future_item.callback()
    assert.is_true(stats.settings.calendar_browse_future_months)

    -- Daily timeline start
    local timeline_start_item = settings_sub[7]
    assert.is_string(timeline_start_item.text_func())
    timeline_start_item.callback(dummy_menu)

    -- Use day time shift
    local time_shift_item = settings_sub[8]
    time_shift_item.callback()
    assert.is_true(stats.settings.calendar_use_day_time_shift)
  end)

  it("should handle toggle statistics action", function()
    local stats = createInstance()
    assert.is_true(stats.settings.is_enabled)

    stats:onToggleStatistics(true)
    assert.is_false(stats.settings.is_enabled)

    stats:onToggleStatistics(true)
    assert.is_true(stats.settings.is_enabled)
    assert.stub(UIManager.broadcastEvent).was_called_with(match.ref(UIManager), "UpdateFooter")
  end)

  it("should open statistics sub-views and menus", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 10, 10 } }
    stats:insertDB()

    -- statMenu
    stats:statMenu()
    assert.stub(UIManager.show).was_called()
    assert.is_table(stats.kv)

    -- View launchers
    stats:onShowCalendarView()
    assert.stub(UIManager.show).was_called()

    stats:onShowCalendarDayView()
    assert.stub(UIManager.show).was_called()

    stats:onShowReaderProgress()
    assert.stub(UIManager.show).was_called()

    -- Test onShowReaderProgress
    stats:onShowReaderProgress()
    assert.stub(UIManager.show).was_called()

    stats:onShowBookStats()
    assert.stub(UIManager.show).was_called()
  end)

  it("should handle period callbacks", function()
    local stats = createInstance()
    stats:callbackMonthly(0, 100, "Jan 2026", false)
    assert.stub(UIManager.show).was_called()

    stats:callbackMonthly(0, 100, "Jan 2026", true)
    assert.stub(UIManager.show).was_called()

    stats:callbackWeekly(0, 100, "Week 1", false)
    assert.stub(UIManager.show).was_called()

    stats:callbackWeekly(0, 100, "Week 1", true)
    assert.stub(UIManager.show).was_called()

    stats:callbackDaily(0, 100, "2026-01-01")
    assert.stub(UIManager.show).was_called()
  end)

  it("should fetch statistics queries accurately", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 10, 10 } }
    stats:insertDB()

    local current_stat = stats:getCurrentStat()
    assert.is_table(current_stat)
    assert.is_true(#current_stat > 0)

    local book_stat = stats:getBookStat(stats.id_curr_book)
    assert.is_table(book_stat)
    assert.is_true(#book_stat > 0)

    local today_dur, today_pages = stats:getTodayBookStats()
    assert.is_number(today_dur)
    assert.is_number(today_pages)

    local cur_dur, cur_pages = stats:getCurrentBookStats()
    assert.is_number(cur_dur)
    assert.is_number(cur_pages)

    local status_stats = stats:getStatsBookStatus(stats.id_curr_book, true)
    assert.is_table(status_stats)

    local total_msg, total_stats = stats:getTotalStats()
    assert.is_string(total_msg)
    assert.is_table(total_stats)
  end)

  it("should retrieve dates and books stats periods", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 20, 20 } }
    stats:insertDB()

    local daily = stats:getDatesFromAll(7, "daily")
    assert.is_table(daily)

    local weekly = stats:getDatesFromAll(0, "weekly", true)
    assert.is_table(weekly)

    local monthly = stats:getDatesFromAll(0, "monthly", true)
    assert.is_table(monthly)

    local progress = stats:getReadingProgressStats(7)
    assert.is_table(progress)

    local dates_for_book = stats:getDatesForBook(stats.id_curr_book)
    assert.is_table(dates_for_book)

    local per_hour = stats:getReadingRatioPerHourByDay(os.date("%Y-%m"))
    assert.is_table(per_hour)

    local by_day = stats:getReadBookByDay(os.date("%Y-%m"))
    assert.is_table(by_day)

    local by_sec = stats:getReadingDurationBySecond(os.time())
    assert.is_table(by_sec)

    local read_pages = stats:getCurrentBookReadPages()
    assert.is_table(read_pages)

    local first_ts = stats:getFirstTimestamp()
    assert.is_number(first_ts)
  end)

  it("should handle deleting and resetting statistics", function()
    local stats = createInstance()
    stats.curr_page = 1
    stats.page_stat[1] = { { os.time() - 10, 10 } }
    stats:insertDB()

    local id = stats.id_curr_book
    assert.is_number(id)

    -- Reset routines
    stats:resetCurrentBook()
    assert.stub(UIManager.show).was_called()

    stats:resetPerBook()
    assert.stub(UIManager.show).was_called()

    stats:deleteBooksByTotalDuration(5)
    assert.stub(UIManager.show).was_called()

    stats:resetStatsForBookForPeriod(id, 0, 1000, "2026-01-01", function() end)
    assert.stub(UIManager.show).was_called()

    -- Delete book directly
    stats:deleteBook(id)

    local conn = SQ3.open(db_location)
    local count = conn:rowexec(string.format("SELECT count(*) FROM book WHERE id = %d;", id))
    conn:close()
    assert.are.equal(0, tonumber(count))
  end)

  it("should handle sync check, triggers, and onSync callback", function()
    local stats = createInstance()
    assert.is_false(stats:canSync())

    stats.settings.sync_server = { type = "dropbox", url = "http://localhost" }
    assert.is_true(stats:canSync())

    stats:onSyncBookStats()
    assert.stub(UIManager.show).was_called()
    assert.stub(UIManager.nextTick).was_called()

    -- Test onSync function
    local local_db = DataStorage:getSettingsDir() .. "/sync_local.sqlite3"
    local cached_db = DataStorage:getSettingsDir() .. "/sync_cached.sqlite3"
    local income_db = DataStorage:getSettingsDir() .. "/sync_income.sqlite3"

    os.remove(local_db)
    os.remove(cached_db)
    os.remove(income_db)

    local c_loc = SQ3.open(local_db)
    ReaderStatistics:createDB(c_loc)
    c_loc:close()

    local c_inc = SQ3.open(income_db)
    ReaderStatistics:createDB(c_inc)
    c_inc:close()

    local ok = ReaderStatistics.onSync(local_db, cached_db, income_db)
    assert.is_truthy(ok)

    os.remove(local_db)
    os.remove(cached_db)
    os.remove(income_db)
  end)

  it("should register dispatcher actions safely", function()
    if type(ReaderStatistics.onDispatcherRegisterActions) == "function" then
      ReaderStatistics:onDispatcherRegisterActions()
    end
  end)
end)
