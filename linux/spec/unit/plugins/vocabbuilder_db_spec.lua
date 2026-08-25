describe("VocabBuilder DB module", function()
  local DB, DataStorage, SQ3, LuaData, Device
  local test_db_path, test_cached_path, test_income_path

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    DataStorage = require("datastorage")
    SQ3 = require("lua-ljsqlite3/init")
    LuaData = require("luadata")
    Device = require("device")

    test_db_path = DataStorage:getSettingsDir() .. "/vocabulary_builder_test.sqlite3"
    test_cached_path = DataStorage:getSettingsDir() .. "/vocabulary_builder_cached_test.sqlite3"
    test_income_path = DataStorage:getSettingsDir() .. "/vocabulary_builder_income_test.sqlite3"

    DB = require("plugins/vocabbuilder.koplugin/db")
  end)

  teardown(function()
    os.remove(test_db_path)
    os.remove(test_cached_path)
    os.remove(test_income_path)
    os.remove(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    os.remove(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3")
    DB:init()
  end)

  after_each(function()
    os.remove(DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3")
    os.remove(test_db_path)
    os.remove(test_cached_path)
    os.remove(test_income_path)
  end)

  describe("Schema creation and migration", function()
    it("should create database with default schema and user_version", function()
      local conn = SQ3.open(DB.path)
      local version = tonumber(conn:rowexec("PRAGMA user_version;"))
      assert.is_true(version >= 20240905)

      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(0, count)
      conn:close()
    end)

    it("should handle migration from older schemas", function()
      local db_file = DB.path
      os.remove(db_file)
      local conn = SQ3.open(db_file)
      -- Setup an old schema (version 20210101) with old columns
      conn:exec([[
        CREATE TABLE "vocabulary" (
          "word" TEXT NOT NULL UNIQUE,
          "book_title" TEXT,
          "create_time" INTEGER NOT NULL,
          "review_time" INTEGER,
          "due_time" INTEGER NOT NULL,
          "review_count" INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY("word")
        );
        CREATE TABLE "title" (
          "id" INTEGER NOT NULL UNIQUE,
          "name" TEXT UNIQUE,
          PRIMARY KEY("id")
        );
        INSERT INTO "vocabulary" (word, book_title, create_time, due_time) VALUES ('oldword', 'Old Book', 100, 200);
        PRAGMA user_version = 20210101;
      ]])
      conn:close()

      -- Call createDB to run migration steps
      DB:createDB()

      conn = SQ3.open(db_file)
      local version = tonumber(conn:rowexec("PRAGMA user_version;"))
      assert.are.equal(20240905, version)

      -- Check migrated columns and data
      local row = conn:exec("SELECT word, title_id, streak_count, highlight FROM vocabulary WHERE word='oldword';")
      assert.is_table(row)
      assert.are.equal("oldword", row.word[1])
      assert.is_not_nil(row.title_id[1])
      conn:close()
    end)

    it("should import lookup data from lookup_history.lua when version is 0", function()
      local history_file = DataStorage:getSettingsDir() .. "/lookup_history.lua"
      os.remove(history_file)
      local lh = LuaData:open(history_file, "LookupHistory")
      lh:addTableItem({ word = "hist1", book_title = "Hist Book 1", time = 1000 })
      lh:addTableItem({ word = "hist2", book_title = "Hist Book 1", time = 2000 })
      lh:addTableItem({ word = "hist1", book_title = "Hist Book 1", time = 3000 }) -- duplicate word

      local db_file = DB.path
      os.remove(db_file)
      local conn = SQ3.open(db_file)
      conn:exec("PRAGMA user_version = 0;")
      conn:close()

      DB:createDB()

      conn = SQ3.open(db_file)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(2, count)
      local t_count = tonumber(conn:rowexec("SELECT count(0) FROM title;"))
      assert.are.equal(1, t_count)
      conn:close()

      os.remove(history_file)
    end)
  end)

  describe("Query and pagination methods", function()
    before_each(function()
      for i = 1, 10 do
        DB:insertOrUpdate({
          word = "word" .. string.format("%02d", i),
          book_title = (i <= 5) and "Book Alpha" or "Book Beta",
          time = 1000 + i * 10,
          prev_context = "prev " .. i,
          next_context = "next " .. i,
          highlight = "word" .. string.format("%02d", i),
        })
      end
    end)

    it("should count words with selectCount for search and regular filter modes", function()
      -- 1. Normal count
      local dummy_widget = {
        check_reverse = function() return false end,
        reload_time = os.time(),
      }
      local count = DB:selectCount(dummy_widget)
      assert.are.equal(10, count)

      -- 2. Reverse / due time filtered count
      local dummy_widget_rev = {
        check_reverse = function() return true end,
        reload_time = 1050,
      }
      local count_rev = DB:selectCount(dummy_widget_rev)
      assert.is_number(count_rev)

      -- 3. Search query count
      local dummy_widget_search = {
        search_text_sql = "%word0%",
      }
      local count_search = DB:selectCount(dummy_widget_search)
      assert.are.equal(9, count_search)
    end)

    it("should select items with select_items and _select_items", function()
      local items = {}
      for i = 1, 10 do
        table.insert(items, {})
      end

      -- 1. Select with search query
      DB:_select_items(items, 1, nil, "%word01%")
      assert.are.equal("word01", items[1].word)
      assert.are.equal("Book Alpha", items[1].book_title)
      assert.is_function(items[1].got_it_callback)
      assert.is_function(items[1].forgot_callback)
      assert.is_function(items[1].remove_callback)

      -- Test callbacks attached to item
      items[1].got_it_callback(items[1])
      assert.are.equal(1, items[1].streak_count)
      items[1].forgot_callback(items[1])
      assert.are.equal(0, items[1].streak_count)
      items[1].remove_callback(items[1])

      -- 2. Select with normal due_time ordering
      local items2 = {}
      for i = 1, 10 do table.insert(items2, {}) end
      DB:_select_items(items2, 1, nil, nil)
      assert.is_not_nil(items2[1].word)

      -- 3. Select with reverse due_time ordering
      local items3 = {}
      for i = 1, 10 do table.insert(items3, {}) end
      DB:_select_items(items3, 1, os.time() + 10000, nil)
      assert.is_not_nil(items3[1].word)

      -- 4. Test select_items with widget wrapper
      local widget = {
        item_table = {},
        check_reverse = function() return false end,
        reload_time = os.time(),
        search_text_sql = nil,
      }
      for i = 1, 10 do table.insert(widget.item_table, {}) end
      DB:select_items(widget, 0, 10)
      assert.is_not_nil(widget.item_table[1].word)
    end)
  end)

  describe("Spaced repetition gotOrForgot and batch updates", function()
    it("should calculate due times properly across various streak levels", function()
      local item = {
        word = "learn_word",
        review_count = 0,
        streak_count = 0,
        due_time = 0,
      }

      local now = os.time()

      -- Streak 0 -> 1: +30 min (1800s)
      DB:gotOrForgot(item, true)
      assert.are.equal(1, item.streak_count)
      assert.are.equal(1, item.review_count)
      assert.is_true(item.due_time >= now + 1790 and item.due_time <= now + 1810)

      -- Streak 1 -> 2: +12 hr
      DB:gotOrForgot(item, true)
      assert.are.equal(2, item.streak_count)
      assert.are.equal(2, item.review_count)

      -- Streak 2 -> 3: +24 hr
      DB:gotOrForgot(item, true)
      assert.are.equal(3, item.streak_count)

      -- Streak 3 -> 4: +48 hr
      DB:gotOrForgot(item, true)
      assert.are.equal(4, item.streak_count)

      -- Streak 4 -> 5: +96 hr
      DB:gotOrForgot(item, true)
      assert.are.equal(5, item.streak_count)

      -- Streak 5 -> 6: +7 days
      DB:gotOrForgot(item, true)
      assert.are.equal(6, item.streak_count)

      -- Streak 6 -> 7: +15 days
      DB:gotOrForgot(item, true)
      assert.are.equal(7, item.streak_count)

      -- Streak 7 -> 8: +30 days
      DB:gotOrForgot(item, true)
      assert.are.equal(8, item.streak_count)

      -- Streak 8 -> 9: +60 days
      DB:gotOrForgot(item, true)
      assert.are.equal(9, item.streak_count)

      -- Streak 15 -> 16: cap check
      item.streak_count = 15
      DB:gotOrForgot(item, true)
      assert.are.equal(16, item.streak_count)

      -- Test Forgot: resets streak to 0, decrements review count, due in 5 min
      DB:gotOrForgot(item, false)
      assert.are.equal(0, item.streak_count)
      assert.are.equal(item.last_review_count - 1, item.review_count)
      assert.is_true(item.due_time >= now + 290 and item.due_time <= now + 310)
    end)

    it("should batch update reviewed items and clean up orphaned titles", function()
      DB:insertOrUpdate({ word = "batch1", book_title = "Orphan Book", time = 100 })
      DB:insertOrUpdate({ word = "batch2", book_title = "Persistent Book", time = 100 })

      local items = {
        {
          word = "batch1",
          review_count = 3,
          streak_count = 2,
          review_time = 500,
          due_time = 1500,
        },
        {
          word = "batch2",
          review_count = 1,
          streak_count = 1,
          review_time = nil, -- not reviewed, should be skipped
          due_time = 1200,
        },
      }

      DB:batchUpdateItems(items)

      local conn = SQ3.open(DB.path)
      local row = conn:exec("SELECT review_count, streak_count FROM vocabulary WHERE word='batch1';")
      assert.are.equal(3, tonumber(row.review_count[1]))
      assert.are.equal(2, tonumber(row.streak_count[1]))

      -- Remove batch1, then batchUpdate to trigger orphan title removal
      conn:exec("DELETE FROM vocabulary WHERE word='batch1';")
      conn:close()

      DB:batchUpdateItems({})

      conn = SQ3.open(DB.path)
      local orphan_count = tonumber(conn:rowexec("SELECT count(0) FROM title WHERE name='Orphan Book';"))
      assert.are.equal(0, orphan_count)
      local persist_count = tonumber(conn:rowexec("SELECT count(0) FROM title WHERE name='Persistent Book';"))
      assert.are.equal(1, persist_count)
      conn:close()
    end)
  end)

  describe("Book management and title operations", function()
    it("should insert, change, and query books and book IDs", function()
      local id1 = DB:insertNewBook("Fantasy Novel")
      assert.is_number(id1)

      DB:insertOrUpdate({ word = "dragon", book_title = "Fantasy Novel", time = 200 })
      DB:changeBookTitle("Fantasy Novel", "High Fantasy Novel")

      local books = DB:selectBooks()
      local found = false
      for _, b in ipairs(books) do
        if b.name == "High Fantasy Novel" then
          found = true
          assert.is_true(b.filter)
        end
      end
      assert.is_true(found)

      local id2 = DB:insertNewBook("Sci-Fi Novel")
      DB:updateBookIdOfWord("dragon", id2)

      local conn = SQ3.open(DB.path)
      local word_tid = tonumber(conn:rowexec("SELECT title_id FROM vocabulary WHERE word='dragon';"))
      assert.are.equal(id2, word_tid)
      conn:close()

      -- toggleBookFilter
      assert.is_false(DB:hasFilteredBook())
      DB:toggleBookFilter({ [id2] = true })
      assert.is_true(DB:hasFilteredBook())
      DB:toggleBookFilter({ [id2] = true })
      assert.is_false(DB:hasFilteredBook())
    end)
  end)

  describe("Synchronization (onSync)", function()
    it("should handle missing or empty income database", function()
      local conn_income = SQ3.open(test_income_path)
      conn_income:close() -- empty sqlite file with schema_version 0

      local res = DB.onSync(test_db_path, test_cached_path, test_income_path)
      assert.is_true(res)
    end)

    it("should handle invalid local database gracefully", function()
      local conn_income = SQ3.open(test_income_path)
      conn_income:exec([[
        CREATE TABLE "vocabulary" (
          "word" TEXT NOT NULL UNIQUE,
          "title_id" INTEGER,
          "create_time" INTEGER NOT NULL,
          "review_time" INTEGER,
          "due_time" INTEGER NOT NULL,
          "review_count" INTEGER NOT NULL DEFAULT 0,
          "prev_context" TEXT,
          "next_context" TEXT,
          "streak_count" INTEGER NOT NULL DEFAULT 0,
          "highlight" TEXT,
          PRIMARY KEY("word")
        );
        CREATE TABLE "title" (
          "id" INTEGER NOT NULL UNIQUE,
          "name" TEXT UNIQUE,
          "filter" INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY("id")
        );
        PRAGMA user_version = 20240905;
      ]])
      conn_income:close()

      -- test_db_path contains corrupted non-sqlite data
      local f = io.open(test_db_path, "w")
      if f then
        f:write("invalid sqlite binary stream\n")
        f:close()
      end

      local res = DB.onSync(test_db_path, test_cached_path, test_income_path)
      assert.is_false(res)
    end)

    it("should merge income and local databases without cache", function()
      local schema = [[
        CREATE TABLE "vocabulary" (
          "word" TEXT NOT NULL UNIQUE,
          "title_id" INTEGER,
          "create_time" INTEGER NOT NULL,
          "review_time" INTEGER,
          "due_time" INTEGER NOT NULL,
          "review_count" INTEGER NOT NULL DEFAULT 0,
          "prev_context" TEXT,
          "next_context" TEXT,
          "streak_count" INTEGER NOT NULL DEFAULT 0,
          "highlight" TEXT,
          PRIMARY KEY("word")
        );
        CREATE TABLE "title" (
          "id" INTEGER NOT NULL UNIQUE,
          "name" TEXT UNIQUE,
          "filter" INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY("id")
        );
        PRAGMA user_version = 20240905;
      ]]

      -- Create local db
      local conn_local = SQ3.open(test_db_path)
      conn_local:exec(schema)
      conn_local:exec([[
        INSERT INTO title (id, name) VALUES (1, 'Local Book');
        INSERT INTO vocabulary (word, title_id, create_time, due_time, review_count, streak_count)
        VALUES ('common_word', 1, 100, 500, 2, 1);
        INSERT INTO vocabulary (word, title_id, create_time, due_time, review_count, streak_count)
        VALUES ('local_only', 1, 100, 500, 1, 1);
      ]])
      conn_local:close()

      -- Create income db
      local conn_income = SQ3.open(test_income_path)
      conn_income:exec(schema)
      conn_income:exec([[
        INSERT INTO title (id, name) VALUES (1, 'Income Book');
        INSERT INTO vocabulary (word, title_id, create_time, due_time, review_count, streak_count)
        VALUES ('common_word', 1, 200, 800, 3, 2);
        INSERT INTO vocabulary (word, title_id, create_time, due_time, review_count, streak_count)
        VALUES ('income_only', 1, 200, 800, 1, 1);
      ]])
      conn_income:close()

      local res = DB.onSync(test_db_path, test_cached_path, test_income_path)
      assert.is_true(res)

      local conn = SQ3.open(test_db_path)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(3, count)

      -- Common word should have merged review count (2 + 3 = 5 because create_times differed)
      local row = conn:exec("SELECT review_count, streak_count FROM vocabulary WHERE word='common_word';")
      assert.are.equal(5, tonumber(row.review_count[1]))
      conn:close()
    end)

    it("should merge with cached database handling deleted words", function()
      local schema = [[
        CREATE TABLE "vocabulary" (
          "word" TEXT NOT NULL UNIQUE,
          "title_id" INTEGER,
          "create_time" INTEGER NOT NULL,
          "review_time" INTEGER,
          "due_time" INTEGER NOT NULL,
          "review_count" INTEGER NOT NULL DEFAULT 0,
          "prev_context" TEXT,
          "next_context" TEXT,
          "streak_count" INTEGER NOT NULL DEFAULT 0,
          "highlight" TEXT,
          PRIMARY KEY("word")
        );
        CREATE TABLE "title" (
          "id" INTEGER NOT NULL UNIQUE,
          "name" TEXT UNIQUE,
          "filter" INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY("id")
        );
        PRAGMA user_version = 20240905;
      ]]

      -- Local: deleted word 'del_on_local', kept 'del_on_income'
      local conn_local = SQ3.open(test_db_path)
      conn_local:exec(schema)
      conn_local:exec([[
        INSERT INTO title (id, name) VALUES (1, 'Book A');
        INSERT INTO vocabulary (word, title_id, create_time, due_time) VALUES ('del_on_income', 1, 100, 500);
      ]])
      conn_local:close()

      -- Income: kept 'del_on_local', deleted 'del_on_income'
      local conn_income = SQ3.open(test_income_path)
      conn_income:exec(schema)
      conn_income:exec([[
        INSERT INTO title (id, name) VALUES (1, 'Book A');
        INSERT INTO vocabulary (word, title_id, create_time, due_time) VALUES ('del_on_local', 1, 100, 500);
      ]])
      conn_income:close()

      -- Cached: had both
      local conn_cached = SQ3.open(test_cached_path)
      conn_cached:exec(schema)
      conn_cached:exec([[
        INSERT INTO title (id, name) VALUES (1, 'Book A');
        INSERT INTO vocabulary (word, title_id, create_time, due_time) VALUES ('del_on_local', 1, 100, 500);
        INSERT INTO vocabulary (word, title_id, create_time, due_time) VALUES ('del_on_income', 1, 100, 500);
      ]])
      conn_cached:close()

      local res = DB.onSync(test_db_path, test_cached_path, test_income_path)
      assert.is_true(res)

      local conn = SQ3.open(test_db_path)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(0, count)
      conn:close()
    end)
  end)
end)
