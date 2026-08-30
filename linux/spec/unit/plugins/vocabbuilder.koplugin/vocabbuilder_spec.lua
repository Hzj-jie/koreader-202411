describe("VocabBuilder plugin unit tests", function()
  local Dispatcher, UIManager, DataStorage, G_reader_settings, SQ3, Event, Blitbuffer
  local VocabBuilder, DB
  local mock_ui, db_location

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    G_reader_settings = require("luasettings"):open("reader")
    DataStorage = require("datastorage")
    SQ3 = require("lua-ljsqlite3/init")
    Event = require("ui/event")
    Blitbuffer = require("ffi/blitbuffer")
    db_location = DataStorage:getSettingsDir() .. "/vocabulary_builder.sqlite3"

    DB = require("plugins/vocabbuilder.koplugin/db")
    DB:init()

    VocabBuilder = require("plugins/vocabbuilder.koplugin/main")
  end)

  teardown(function()
    os.remove(db_location)
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
  end)

  before_each(function()
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")

    stub(Dispatcher, "registerAction")
    stub(UIManager, "show")
    stub(UIManager, "close")
    stub(UIManager, "setDirty")
    stub(UIManager, "broadcastEvent")

    os.remove(db_location)
    DB:init()

    mock_ui = {
      menu = {
        registerToMainMenu = spy.new(function() end),
      },
      highlight = {
        getSelectedWordContext = function()
          return "prefix context ", " suffix context"
        end,
        selected_text = {
          text = "highlighted word",
        },
      },
    }
  end)

  after_each(function()
    Dispatcher.registerAction:revert()
    UIManager.show:revert()
    UIManager.close:revert()
    UIManager.setDirty:revert()
    UIManager.broadcastEvent:revert()

    os.remove(db_location)
  end)

  local function findShownWidget(predicate)
    for _, call in ipairs(UIManager.show.calls) do
      local widget = call.refs[2]
      if widget and predicate(widget) then
        return widget
      end
    end
    return nil
  end

  local function getMenuDialog(builder)
    builder:onShowVocabBuilder()
    builder.widget:onShowMenu()
    return findShownWidget(function(w)
      return w.setupPluginMenu ~= nil
    end)
  end

  describe("Plugin initialization & registration", function()
    it("should export VocabBuilder widget container", function()
      assert.is_table(VocabBuilder)
      assert.are.equal("vocabulary_builder", VocabBuilder.name)
    end)

    it("registers dispatcher action and main menu item", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:init()

      assert.stub(Dispatcher.registerAction).was_called()
      assert.spy(mock_ui.menu.registerToMainMenu).was_called_with(mock_ui.menu, builder)
    end)

    it("adds vocabulary builder item to main menu", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu_items = {}
      builder:addToMainMenu(menu_items)

      assert.is_table(menu_items.vocabbuilder)
      assert.is_function(menu_items.vocabbuilder.callback)
    end)
  end)

  describe("Database initialization & schema", function()
    it("initializes SQLite database table and schema", function()
      local conn = SQ3.open(db_location)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(0, count)

      local title_count = tonumber(conn:rowexec("SELECT count(0) FROM title;"))
      assert.are.equal(0, title_count)
      conn:close()
    end)

    it("inserts and updates lookup data correctly", function()
      DB:insertOrUpdate({
        word = "testword",
        book_title = "Test Book",
        time = os.time(),
        prev_context = "prev",
        next_context = "next",
      })

      local conn = SQ3.open(db_location)
      local word_count = tonumber(
        conn:rowexec("SELECT count(0) FROM vocabulary WHERE word='testword';")
      )
      assert.are.equal(1, word_count)

      local title_count = tonumber(
        conn:rowexec("SELECT count(0) FROM title WHERE name='Test Book';")
      )
      assert.are.equal(1, title_count)
      conn:close()
    end)

    it("resets progress and purges database", function()
      DB:insertOrUpdate({ word = "word1", book_title = "Book A", time = os.time() })
      DB:insertOrUpdate({ word = "word2", book_title = "Book A", time = os.time() })

      DB:resetProgress()
      local conn = SQ3.open(db_location)
      local rev_count = tonumber(conn:rowexec("SELECT sum(review_count) FROM vocabulary;"))
      assert.are.equal(0, rev_count)

      DB:purge()
      local total_words = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      assert.are.equal(0, total_words)
      conn:close()
    end)
  end)

  describe("Word lookup events (onWordLookedUp)", function()
    it("skips auto-adding word when disabled and not manual", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 1)

      local res = builder:onWordLookedUp("apple", "Test Book", false)
      assert.is_nil(res)

      local conn = SQ3.open(db_location)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
      conn:close()
      assert.are.equal(0, count)
    end)

    it("adds word when is_manual is true even if auto-add disabled", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 1)

      local res = builder:onWordLookedUp("apple", "Test Book", true)
      assert.is_true(res)

      local conn = SQ3.open(db_location)
      local count = tonumber(conn:rowexec("SELECT count(0) FROM vocabulary WHERE word='apple';"))
      conn:close()
      assert.are.equal(1, count)
    end)

    it("adds word with context when enabled and context option on", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 2)
      menu:onChangeContextStatus(nil, 2)

      local res = builder:onWordLookedUp("banana", "Test Book", false)
      assert.is_true(res)

      local conn = SQ3.open(db_location)
      local row = conn:rowexec("SELECT prev_context, next_context, highlight FROM vocabulary WHERE word='banana';")
      conn:close()
      assert.is_not_nil(row)
    end)
  end)

  describe("Dictionary popup integration (onDictButtonsReady)", function()
    it("adds vocabulary button to popup when disabled", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 1)

      local dict_popup = {
        lookupword = "cherry",
        ui = { doc_props = { display_title = "Book Title" } },
        button_table = { button_by_id = {} },
      }
      local buttons = {}
      builder:onDictButtonsReady(dict_popup, buttons)

      assert.are.equal(1, #buttons)
      assert.are.equal("vocabulary", buttons[1][1].id)

      buttons[1][1].callback()
      assert.stub(UIManager.broadcastEvent).was_called()
    end)
  end)

  describe("VocabularyBuilderWidget & UI workflows", function()
    it("creates widget, paints to Blitbuffer, and tests UI actions", function()
      DB:insertOrUpdate({ word = "word1", book_title = "Book 1", time = os.time(), prev_context = "pre", next_context = "post", highlight = "word1" })
      DB:insertOrUpdate({ word = "word2", book_title = "Book 2", time = os.time() })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()

      local widget = builder.widget
      assert.is_table(widget)
      assert.are.equal(2, #widget.item_table)

      -- Paint widget to Blitbuffer
      local bb = Blitbuffer.new(600, 800)
      widget:paintTo(bb, 0, 0)

      -- Exercise item widgets inside
      for _, item in ipairs(widget.main_content) do
        if item.item and item.item.paintTo then
          item.item:paintTo(bb, 0, 0)
        end
      end

      -- Test filter dialog
      widget:onShowFilter()

      -- Test change book title dialog
      widget:showChangeBookTitleDialog({ id = 1, name = "Book 1" }, function() end)

      -- Close
      widget:onExit()
    end)

    it("handles pagination next, prev, and page navigation", function()
      for i = 1, 20 do
        DB:insertOrUpdate({ word = "word" .. i, book_title = "Book 1", time = os.time() })
      end

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      assert.are.equal(1, widget.show_page)
      widget:nextPage()
      assert.is_true(widget.show_page > 1)
      widget:prevPage()
      assert.are.equal(1, widget.show_page)
      widget:goToPage(2)
      assert.are.equal(2, widget.show_page)
    end)

    it("handles search dialog and filtering", function()
      DB:insertOrUpdate({ word = "apple", book_title = "Fruit", time = os.time() })
      DB:insertOrUpdate({ word = "apricot", book_title = "Fruit", time = os.time() })
      DB:insertOrUpdate({ word = "banana", book_title = "Fruit", time = os.time() })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      widget:showSearchDialog()
      widget.search_text = "ap"
      widget.search_text_sql = "%ap%"
      widget:reloadItems()

      assert.are.equal(2, #widget.item_table)
      widget:onExit()
    end)

    it("handles VocabItemWidget review actions, showMore, detail and dict integration", function()
      DB:insertOrUpdate({
        word = "testword",
        book_title = "Test Book",
        time = os.time() - 100,
        due_time = os.time() - 100,
        prev_context = "prefix ",
        next_context = " suffix",
        highlight = "testword",
      })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      assert.is_true(#widget.item_table >= 1)
      local item_entry = widget.item_table[1]
      assert.is_table(item_entry)

      -- Exercise VocabItemWidget via main_content
      for _, item in ipairs(widget.main_content) do
        local item_widget = item.item
        if item_widget and item_widget.item then
          -- Time since due
          local time_str = item_widget:getTimeSinceDue()
          assert.is_string(time_str)

          -- Review callbacks: onGotIt and onForgot
          if item_widget.onGotIt then
            item_widget:onGotIt()
            assert.is_true(item_widget.item.is_dim)
          end
          if item_widget.onForgot then
            item_widget:onForgot(true) -- no_lookup = true
            assert.is_false(item_widget.item.is_dim)
          end

          -- showMore / onShowDetail / onShowBookAssignment
          if item_widget.showMore then
            item_widget:showMore()
          end
          if item_widget.onShowDetail then
            item_widget:onShowDetail()
          end
          if item_widget.onShowBookAssignment then
            item_widget:onShowBookAssignment(function() end)
          end

          -- onDictButtonsReady hook
          local dict_popup = { word = item_widget.item.word, onExit = function() end }
          local dict_buttons = {
            { { id = "highlight", enabled = false }, { id = "search", enabled = false } },
          }
          item_widget:onDictButtonsReady(dict_popup, dict_buttons)
          assert.are.equal("got_it", dict_buttons[1][1].id)
          assert.are.equal("forgot", dict_buttons[1][2].id)
        end
      end

      widget:onExit()
    end)

    it("handles MenuDialog actions, study settings, and DB methods", function()
      DB:insertOrUpdate({ word = "word_db1", book_title = "Book A", time = os.time() })
      DB:insertOrUpdate({ word = "word_db2", book_title = "Book B", time = os.time() })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      -- Menu dialog
      local menu_dialog = getMenuDialog(builder)
      assert.is_table(menu_dialog)

      -- Test DB methods
      local books = DB:selectBooks()
      assert.is_table(books)
      assert.is_true(#books >= 2)

      local new_id = DB:insertNewBook("Virtual Book 1")
      assert.is_number(new_id)
      DB:changeBookTitle("Virtual Book 1", "Renamed Book 1")
      DB:updateBookIdOfWord("word_db1", new_id)

      DB:toggleBookFilter({ [new_id] = true })
      assert.is_true(DB:hasFilteredBook())
      DB:toggleBookFilter({ [new_id] = true })
      assert.is_false(DB:hasFilteredBook())

      -- gotOrForgot
      local item = widget.item_table[1]
      if item then
        DB:gotOrForgot(item, true)
        DB:gotOrForgot(item, false)
        DB:remove(item)
      end

      widget:onExit()
    end)
  end)
end)
