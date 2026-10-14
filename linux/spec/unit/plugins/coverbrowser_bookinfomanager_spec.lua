-- luacheck: ignore 122
describe("CoverBrowser BookInfoManager plugin module", function()
  local BookInfoManager, FFIUtil, UIManager, Trapper, DocumentRegistry
  local util, SQ3
  local test_db_path

  setup(function()
    require("commonrequire")
    BookInfoManager = require("plugins/coverbrowser.koplugin/bookinfomanager")
    FFIUtil = require("ffi/util")
    UIManager = require("ui/uimanager")
    Trapper = require("ui/trapper")
    DocumentRegistry = require("document/documentregistry")
    util = require("util")
    SQ3 = require("lua-ljsqlite3/init")

    test_db_path = "/tmp/test_coverbrowser_bim_"
      .. FFIUtil.getpid()
      .. ".sqlite3"
  end)

  local orig_sleep

  before_each(function()
    BookInfoManager:init()
    BookInfoManager.db_location = test_db_path
    BookInfoManager.db_created = false
    orig_sleep = FFIUtil.sleep
    FFIUtil.sleep = function() end
  end)

  after_each(function()
    FFIUtil.sleep = orig_sleep
    BookInfoManager:closeDbConnection()
    BookInfoManager:deleteDb()
    os.remove(test_db_path)
    os.remove(test_db_path .. "-wal")
    os.remove(test_db_path .. "-shm")
  end)

  describe("Database initialization and schema management", function()
    it("initializes default properties and settings", function()
      assert.is_table(BookInfoManager)
      assert.is_number(BookInfoManager.max_extract_tries)
      assert.is_string(BookInfoManager.db_location)
    end)

    it("creates SQLite database and establishes connection", function()
      assert.is_false(BookInfoManager.db_created or false)
      BookInfoManager:createDB()
      assert.is_true(BookInfoManager.db_created)

      BookInfoManager:openDbConnection()
      assert.is_not_nil(BookInfoManager.db_conn)
      assert.is_not_nil(BookInfoManager.set_stmt)
      assert.is_not_nil(BookInfoManager.get_stmt)
      assert.is_not_nil(BookInfoManager.in_progress_stmt)

      local count = BookInfoManager:getBookCount()
      assert.are.equal(0, count)

      local size_str = BookInfoManager:getDbSize()
      assert.is_string(size_str)

      BookInfoManager:closeDbConnection()
      assert.is_nil(BookInfoManager.db_conn)
    end)

    it("compacts database via compactDb vacuum", function()
      BookInfoManager:createDB()
      local result = BookInfoManager:compactDb()
      assert.is_string(result)
      assert.is_truthy(result:match("size reduced") or result:match("Failed"))
    end)
  end)

  describe("Configuration and settings management", function()
    it("saves, retrieves, and toggles settings in config table", function()
      BookInfoManager:createDB()
      BookInfoManager:save("test_key", "test_val")
      assert.are.equal("test_val", BookInfoManager:getSetting("test_key"))

      BookInfoManager:save("flag_bool", true)
      assert.are.equal("Y", BookInfoManager:getSetting("flag_bool"))

      local toggled = BookInfoManager:toggleSetting("toggle_flag")
      assert.is_true(toggled)
      assert.are.equal("Y", BookInfoManager:getSetting("toggle_flag"))

      local toggled_back = BookInfoManager:toggleSetting("toggle_flag")
      assert.is_false(toggled_back)
      assert.is_nil(BookInfoManager:getSetting("toggle_flag"))
    end)
  end)

  describe("Cover calculations and geometry helpers", function()
    it(
      "calculates proportional cached cover dimensions in getCachedCoverSize",
      function()
        local w, h, scale =
          BookInfoManager.getCachedCoverSize(400, 800, 200, 200)
        assert.are.equal(100, w)
        assert.are.equal(200, h)
        assert.are.equal(0.25, scale)

        local w2, h2, scale2 =
          BookInfoManager.getCachedCoverSize(800, 400, 200, 200)
        assert.are.equal(200, w2)
        assert.are.equal(100, h2)
        assert.are.equal(0.25, scale2)
      end
    )

    it(
      "detects invalid cached covers when specs change in isCachedCoverInvalid",
      function()
        local bookinfo_nocover = { cover_w = nil, cover_h = nil }
        assert.is_true(
          BookInfoManager.isCachedCoverInvalid(bookinfo_nocover, {})
        )

        local bookinfo_withcover = {
          cover_w = 100,
          cover_h = 150,
          cover_sizetag = "400x600",
        }
        local matching_specs = {
          max_cover_w = 100,
          max_cover_h = 150,
        }
        assert.is_nil(
          BookInfoManager.isCachedCoverInvalid(
            bookinfo_withcover,
            matching_specs
          )
        )

        local larger_specs = {
          max_cover_w = 200,
          max_cover_h = 300,
        }
        assert.is_true(
          BookInfoManager.isCachedCoverInvalid(bookinfo_withcover, larger_specs)
        )
      end
    )
  end)

  describe("Book information retrieval", function()
    it(
      "returns synthetic bookinfo for directories and unsupported files without querying db",
      function()
        local dir_info = BookInfoManager:getBookInfo("/tmp", false)
        assert.is_table(dir_info)
        assert.is_true(dir_info._is_directory)
        assert.are.equal(0, dir_info.in_progress)

        local nonbook_info = BookInfoManager:getBookInfo(
          "/tmp/nonexistent_file.xyz_unsupported",
          false
        )
        assert.is_table(nonbook_info)
        assert.is_true(nonbook_info._no_provider)
      end
    )

    it("returns nil for unindexed valid book formats", function()
      local orig_has = DocumentRegistry.hasProvider
      DocumentRegistry.hasProvider = function()
        return true
      end
      finally(function()
        DocumentRegistry.hasProvider = orig_has
      end)

      BookInfoManager:createDB()
      local info =
        BookInfoManager:getBookInfo("/tmp/unindexed_book.epub", false)
      assert.is_nil(info)
    end)
  end)

  describe("Defect verifications", function()
    it(
      "fails: exposes missing #files count in N_() call at line 1054 producing plural text for 1 book",
      function()
        local captured_messages = {}
        local orig_show = UIManager.show
        local orig_close = UIManager.close
        local orig_repaint = UIManager.forceRepaint
        local orig_sleep = FFIUtil.sleep
        local orig_confirm = Trapper.confirm
        local orig_run_sub = Trapper.dismissableRunInSubprocess
        local orig_clear = Trapper.clear
        local orig_term = BookInfoManager.terminateBackgroundJobs

        UIManager.show = function(_, widget)
          if widget and widget.text then
            table.insert(captured_messages, widget.text)
          end
        end
        UIManager.close = function() end
        UIManager.forceRepaint = function() end
        FFIUtil.sleep = function() end
        BookInfoManager.terminateBackgroundJobs = function() end

        -- Trapper:confirm responses:
        -- 1: go_on (true)
        -- 2: recursive (true)
        -- 3: refresh_existing (false) -> triggers line 1054!
        -- 4: prune (false)
        local confirm_step = 0
        Trapper.confirm = function()
          confirm_step = confirm_step + 1
          if confirm_step == 1 then
            return true
          elseif confirm_step == 2 then
            return true
          elseif confirm_step == 3 then
            return false
          elseif confirm_step == 4 then
            return false
          end
          return false
        end

        Trapper.clear = function() end

        -- First run: finds 1 book.
        -- Second run: finds 1 book needing indexing.
        local run_sub_step = 0
        Trapper.dismissableRunInSubprocess = function()
          run_sub_step = run_sub_step + 1
          if run_sub_step == 1 then
            return true, { "/tmp/book1.epub" }
          elseif run_sub_step == 2 then
            return true, { "/tmp/book1.epub" }
          else
            return true, true
          end
        end

        -- Stub extractBookInfo to immediately succeed
        local orig_extract = BookInfoManager.extractBookInfo
        BookInfoManager.extractBookInfo = function()
          return true
        end

        finally(function()
          UIManager.show = orig_show
          UIManager.close = orig_close
          UIManager.forceRepaint = orig_repaint
          FFIUtil.sleep = orig_sleep
          Trapper.confirm = orig_confirm
          Trapper.dismissableRunInSubprocess = orig_run_sub
          Trapper.clear = orig_clear
          BookInfoManager.terminateBackgroundJobs = orig_term
          BookInfoManager.extractBookInfo = orig_extract
        end)

        pcall(function()
          BookInfoManager:extractBooksInDirectory("/tmp/dummy_dir", {})
        end)

        -- Find the "Found ... book... to index." message
        local found_msg = nil
        for _, msg in ipairs(captured_messages) do
          if msg:match("to index%.") then
            found_msg = msg
            break
          end
        end

        assert.is_not_nil(found_msg)
        -- For 1 book, the correct grammar is singular: "Found 1 book to index."
        -- Due to N_() missing the 3rd argument #files at line 1054,
        -- GetText.getPlural(nil) defaults to plural, yielding "Found 1 books to index."
        assert.are.equal("Found 1 book to index.", found_msg)
      end
    )
  end)
end)
