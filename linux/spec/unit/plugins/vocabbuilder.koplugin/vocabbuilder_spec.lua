describe("VocabBuilder plugin unit tests", function()
  local Dispatcher, UIManager, DataStorage, G_reader_settings, SQ3, Event
  local VocabBuilder, VocabularyBuilderWidget, VocabItemWidget, MenuDialog, WordInfoDialog, DB
  local mock_ui, db_location

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    G_reader_settings = require("luasettings"):open("reader")
    DataStorage = require("datastorage")
    SQ3 = require("lua-ljsqlite3/init")
    Event = require("ui/event")
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
      assert
        .spy(mock_ui.menu.registerToMainMenu)
        .was_called_with(mock_ui.menu, builder)
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
      DB:insertOrUpdate({
        word = "word1",
        book_title = "Book A",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "word2",
        book_title = "Book A",
        time = os.time(),
      })

      DB:resetProgress()
      local conn = SQ3.open(db_location)
      local rev_count =
        tonumber(conn:rowexec("SELECT sum(review_count) FROM vocabulary;"))
      assert.are.equal(0, rev_count)

      DB:purge()
      local total_words =
        tonumber(conn:rowexec("SELECT count(0) FROM vocabulary;"))
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
      local count = tonumber(
        conn:rowexec("SELECT count(0) FROM vocabulary WHERE word='apple';")
      )
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
      local row = conn:rowexec(
        "SELECT prev_context, next_context, highlight FROM vocabulary WHERE word='banana';"
      )
      conn:close()
      assert.is_not_nil(row)
    end)

    it("ignores current lookup word when re-looked up", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 2)

      builder.widget = { current_lookup_word = "cherry" }
      local res = builder:onWordLookedUp("cherry", "Test Book", false)
      assert.is_true(res)
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

      -- Execute button callback
      buttons[1][1].callback()
      assert.stub(UIManager.broadcastEvent).was_called()
    end)

    it("does not add button when enabled or wiki fullpage", function()
      local builder = VocabBuilder:new({ ui = mock_ui })
      local menu = getMenuDialog(builder)
      menu:onChangeEnableStatus(nil, 2)

      local dict_popup = { lookupword = "cherry", ui = {} }
      local buttons = {}
      builder:onDictButtonsReady(dict_popup, buttons)
      assert.are.equal(0, #buttons)

      menu:onChangeEnableStatus(nil, 1)
      dict_popup.is_wiki_fullpage = true
      buttons = {}
      builder:onDictButtonsReady(dict_popup, buttons)
      assert.are.equal(0, #buttons)
    end)
  end)

  describe("VocabularyBuilderWidget & UI workflows", function()
    it("creates widget and displays items", function()
      DB:insertOrUpdate({
        word = "word1",
        book_title = "Book 1",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "word2",
        book_title = "Book 2",
        time = os.time(),
      })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()

      assert.stub(UIManager.show).was_called()
      local widget = builder.widget
      assert.is_table(widget)
      assert.are.equal(2, #widget.item_table)
    end)

    it("handles pagination next, prev, and page navigation", function()
      for i = 1, 20 do
        DB:insertOrUpdate({
          word = "word" .. i,
          book_title = "Book 1",
          time = os.time(),
        })
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
      DB:insertOrUpdate({
        word = "apple",
        book_title = "Fruit",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "apricot",
        book_title = "Fruit",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "banana",
        book_title = "Fruit",
        time = os.time(),
      })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      widget:showSearchDialog()
      local dialog = findShownWidget(function(w)
        return w.input ~= nil
      end)
      assert.is_table(dialog)

      widget.search_text = "ap"
      widget.search_text_sql = "%ap%"
      widget:reloadItems()

      assert.are.equal(2, #widget.item_table)
    end)

    it("handles item study callbacks (gotIt and forgot)", function()
      DB:insertOrUpdate({
        word = "memorize",
        book_title = "Study",
        time = os.time(),
      })
      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      local item = widget.item_table[1]
      item.review_count = 0
      item.streak_count = 0
      item.due_time = os.time()

      DB:gotOrForgot(item, true)
      assert.are.equal(1, item.streak_count)
      assert.are.equal(1, item.review_count)

      DB:gotOrForgot(item, false)
      assert.are.equal(0, item.streak_count)
      assert.are.equal(0, item.review_count)
    end)

    it("handles widget removal and reset items", function()
      DB:insertOrUpdate({
        word = "rem1",
        book_title = "Book A",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "rem2",
        book_title = "Book A",
        time = os.time(),
      })

      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      assert.are.equal(2, #widget.item_table)
      widget:removeAt(1)
      assert.are.equal(1, #widget.item_table)

      widget:resetItems()
      assert.are.equal(1, #widget.item_table)
    end)

    it("handles swipe and multi-swipe gestures", function()
      DB:insertOrUpdate({
        word = "swipe1",
        book_title = "Book A",
        time = os.time(),
      })
      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      widget:onSwipe(nil, { direction = "west" })
      widget:onSwipe(nil, { direction = "east" })
      widget:onSwipe(nil, { direction = "south" })
      assert.stub(UIManager.close).was_called()

      local res = widget:onMultiSwipe(
        nil,
        { multiswipe_directions = "east south west north" }
      )
      assert.is_true(res)
    end)
  end)

  describe("Book management & title filtering", function()
    it("toggles book filter and changes book titles", function()
      DB:insertOrUpdate({
        word = "wordA",
        book_title = "Book A",
        time = os.time(),
      })
      DB:insertOrUpdate({
        word = "wordB",
        book_title = "Book B",
        time = os.time(),
      })

      local books = DB:selectBooks()
      assert.are.equal(2, #books)

      -- Change title
      DB:changeBookTitle("Book A", "Renamed Book A")
      books = DB:selectBooks()
      local found = false
      for _, b in ipairs(books) do
        if b.name == "Renamed Book A" then
          found = true
        end
      end
      assert.is_true(found)

      -- Toggle filter
      local book_id = books[1].id
      DB:toggleBookFilter({ [book_id] = true })
      assert.is_true(DB:hasFilteredBook())
    end)
  end)

  describe("MenuDialog and WordInfoDialog components", function()
    it("sets up plugin menu dialog and toggles settings", function()
      DB:insertOrUpdate({
        word = "dialog_word",
        book_title = "Book",
        time = os.time(),
      })
      local builder = VocabBuilder:new({ ui = mock_ui })
      builder:onShowVocabBuilder()
      local widget = builder.widget

      widget:onShowMenu()
      assert.stub(UIManager.show).was_called()

      local menu_widget = findShownWidget(function(w)
        return w.setupPluginMenu ~= nil
      end)
      assert.is_table(menu_widget)
    end)
  end)
end)
