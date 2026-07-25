describe("VocabBuilder plugin", function()
  local VocabBuilder
  local DB
  local Dispatcher
  local UIManager

  setup(function()
    require("commonrequire")
    VocabBuilder = require("plugins/vocabbuilder.koplugin/main")
    DB = require("plugins/vocabbuilder.koplugin/db")
    Dispatcher = require("dispatcher")
    UIManager = require("ui/uimanager")
  end)

  before_each(function()
    DB:purge()
    local settings = G_reader_settings:readTableRef(
      "vocabulary_builder",
      { enabled = false, with_context = true }
    )
    settings.enabled = false
    settings.with_context = true
    settings.reverse = nil
    settings.server = nil
  end)

  after_each(function()
    DB:purge()
  end)

  it("should initialize VocabBuilder class", function()
    assert.is_table(VocabBuilder)
    assert.is_function(VocabBuilder.new)
  end)

  it(
    "should populate main menu items and register dispatcher actions",
    function()
      local vb = VocabBuilder:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })
      local items = {}
      vb:addToMainMenu(items)
      assert.is_table(items.vocabbuilder)
      assert.is_function(items.vocabbuilder.callback)

      vb:onDispatcherRegisterActions()
    end
  )

  describe("onWordLookedUp and word saving", function()
    it(
      "should ignore lookup when plugin is disabled and lookup is automatic",
      function()
        local settings = G_reader_settings:readTableRef("vocabulary_builder")
        settings.enabled = false

        local vb = VocabBuilder:new({
          ui = {
            menu = { registerToMainMenu = function() end },
          },
        })
        local res = vb:onWordLookedUp("testword", "Test Book", false)
        assert.is_nil(res)
        assert.are.equal(
          0,
          DB:selectCount({
            check_reverse = function()
              return false
            end,
          })
        )
      end
    )

    it("should save lookup when plugin is enabled", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      settings.enabled = true

      local vb = VocabBuilder:new({
        ui = {
          menu = { registerToMainMenu = function() end },
        },
      })
      local res = vb:onWordLookedUp("testword", "Test Book", false)
      assert.is_true(res)

      local books = DB:selectBooks()
      assert.are.equal(1, #books)
      assert.are.equal("Test Book", books[1].name)
    end)

    it("should save lookup when lookup is manual even if disabled", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      settings.enabled = false

      local vb = VocabBuilder:new({
        ui = {
          menu = { registerToMainMenu = function() end },
        },
      })
      local res = vb:onWordLookedUp("manualword", "Manual Book", true)
      assert.is_true(res)

      local books = DB:selectBooks()
      assert.are.equal(1, #books)
      assert.are.equal("Manual Book", books[1].name)
    end)

    it(
      "should extract context when enabled and highlight is available",
      function()
        local settings = G_reader_settings:readTableRef("vocabulary_builder")
        settings.enabled = true
        settings.with_context = true

        local vb = VocabBuilder:new({
          ui = {
            menu = { registerToMainMenu = function() end },
            highlight = {
              getSelectedWordContext = function()
                return "before ", " after"
              end,
              selected_text = { text = "highlighted" },
            },
          },
        })
        local res = vb:onWordLookedUp("ctxword", "Context Book", false)
        assert.is_true(res)

        local dummy_widget = {
          check_reverse = function()
            return false
          end,
          item_table = {},
        }
        for _ = 1, DB:selectCount(dummy_widget) do
          table.insert(dummy_widget.item_table, {})
        end
        DB:select_items(dummy_widget, 0, #dummy_widget.item_table)
        assert.are.equal("ctxword", dummy_widget.item_table[1].word)
        assert.are.equal("before ", dummy_widget.item_table[1].prev_context)
        assert.are.equal(" after", dummy_widget.item_table[1].next_context)
        assert.are.equal("highlighted", dummy_widget.item_table[1].highlight)
      end
    )

    it("should skip lookup if current widget lookup word matches", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      settings.enabled = true

      local vb = VocabBuilder:new({
        ui = {
          menu = { registerToMainMenu = function() end },
        },
        widget = { current_lookup_word = "selfword" },
      })
      local res = vb:onWordLookedUp("selfword", "Self Book", false)
      assert.is_true(res)
      assert.are.equal(
        0,
        DB:selectCount({
          check_reverse = function()
            return false
          end,
        })
      )
    end)
  end)

  describe("onDictButtonsReady integration", function()
    it(
      "should add vocabulary button when disabled and not wiki fullpage",
      function()
        local settings = G_reader_settings:readTableRef("vocabulary_builder")
        settings.enabled = false

        local vb = VocabBuilder:new({
          ui = {
            menu = { registerToMainMenu = function() end },
          },
        })

        local dict_popup = {
          is_wiki_fullpage = false,
          lookupword = "popupword",
          ui = { doc_props = { display_title = "Dict Book" } },
          isInWindowStack = function()
            return false
          end,
          button_table = {
            button_by_id = {
              vocabulary = {
                disable = function(self_btn)
                  self_btn.disabled = true
                end,
                dimen = {},
              },
            },
          },
        }
        local buttons = {}
        vb:onDictButtonsReady(dict_popup, buttons)

        assert.are.equal(1, #buttons)
        assert.are.equal("vocabulary", buttons[1][1].id)

        vb:onWordLookedUp(dict_popup.lookupword, "Dict Book", true)
        assert.are.equal(1, #DB:selectBooks())
      end
    )

    it(
      "should not add vocabulary button when enabled or wiki fullpage",
      function()
        local settings = G_reader_settings:readTableRef("vocabulary_builder")
        settings.enabled = true

        local vb = VocabBuilder:new({
          ui = {
            menu = { registerToMainMenu = function() end },
          },
        })

        local buttons = {}
        vb:onDictButtonsReady({ is_wiki_fullpage = false }, buttons)
        assert.are.equal(0, #buttons)

        settings.enabled = false
        buttons = {}
        vb:onDictButtonsReady({ is_wiki_fullpage = true }, buttons)
        assert.are.equal(0, #buttons)
      end
    )
  end)

  describe("MenuDialog and settings toggles", function()
    it("should update settings on status change methods", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      local vb = VocabBuilder:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      vb:onShowVocabBuilder()
      assert.is_table(vb.widget)

      vb.widget:onShowMenu()
      local active_menu =
        UIManager._window_stack[#UIManager._window_stack].widget
      assert.is_table(active_menu)

      active_menu:onChangeEnableStatus(nil, 2)
      assert.is_true(settings.enabled)
      active_menu:onChangeEnableStatus(nil, 1)
      assert.is_false(settings.enabled)

      active_menu:onChangeContextStatus(nil, 2)
      assert.is_true(settings.with_context)
      active_menu:onChangeContextStatus(nil, 1)
      assert.is_false(settings.with_context)

      UIManager:close(active_menu)
      UIManager:close(vb.widget)
    end)
  end)

  describe("VocabItemWidget review and study operations", function()
    it("should calculate time since due correctly across intervals", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      settings.enabled = true
      DB:insertOrUpdate({
        word = "timeword",
        book_title = "Time Book",
        time = os.time() - 3600,
      })

      local vb = VocabBuilder:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      vb:onShowVocabBuilder()

      local vocab_item = vb.widget:vocabItemIter()()
      assert.is_table(vocab_item)

      local now = os.time()
      for _, case in ipairs({
        { due_time = now - 30, pattern = "30s" },
        { due_time = now - 300, pattern = "5m" },
        { due_time = now - 7200, pattern = "2h" },
        { due_time = now - 86400 * 5, pattern = "5d" },
        { due_time = now - 86400 * 60, pattern = "mo." },
        { due_time = now - 86400 * 400, pattern = "yr." },
      }) do
        vocab_item.item.due_time = case.due_time
        local res = vocab_item:getTimeSinceDue()
        assert.is_truthy(res:find(case.pattern))
      end

      UIManager:close(vb.widget)
    end)

    it("should handle onGotIt and onForgot actions", function()
      local settings = G_reader_settings:readTableRef("vocabulary_builder")
      settings.enabled = true
      DB:insertOrUpdate({
        word = "studyword",
        book_title = "Study Book",
        time = os.time(),
      })

      local vb = VocabBuilder:new({
        ui = { menu = { registerToMainMenu = function() end } },
      })
      vb:onShowVocabBuilder()

      local vocab_item = vb.widget:vocabItemIter()()
      assert.is_table(vocab_item)

      vocab_item:onGotIt()
      assert.is_true(vocab_item.item.is_dim)
      assert.are.equal(1, vocab_item.item.streak_count)
      assert.are.equal(1, vocab_item.item.review_count)

      vocab_item:onForgot(true)
      assert.is_false(vocab_item.item.is_dim)
      assert.are.equal(0, vocab_item.item.streak_count)
      assert.are.equal(0, vocab_item.item.review_count)

      vocab_item:resetProgress()
      assert.are.equal(0, vocab_item.item.review_count)
      assert.are.equal(0, vocab_item.item.streak_count)

      vocab_item:undo()
      assert.is_nil(vocab_item.item.last_due_time)

      UIManager:close(vb.widget)
    end)
  end)

  describe("VocabularyBuilderWidget navigation, search and gestures", function()
    it(
      "should handle pagination, search dialog, reverse check and gestures",
      function()
        local settings = G_reader_settings:readTableRef("vocabulary_builder")
        settings.enabled = true

        for i = 1, 5 do
          DB:insertOrUpdate({
            word = "word" .. i,
            book_title = "Book A",
            time = os.time() + i,
          })
        end

        local vb = VocabBuilder:new({
          ui = { menu = { registerToMainMenu = function() end } },
        })
        vb:onShowVocabBuilder()

        local widget = vb.widget
        assert.are.equal(5, #widget.item_table)

        widget:nextPage()
        widget:prevPage()
        widget:goToPage(1)
        assert.are.equal(1, widget.show_page)

        widget:moveItem(3)
        assert.are.equal(1, widget.show_page)

        assert.is_nil(widget:check_reverse())

        widget.search_text = "word1"
        widget.search_text_sql = "%word1%"
        widget:reloadItems()
        assert.are.equal(1, #widget.item_table)
        assert.are.equal("word1", widget.item_table[1].word)

        widget.search_text = ""
        widget.search_text_sql = nil
        widget:reloadItems()
        assert.are.equal(5, #widget.item_table)

        widget:gotItFromDict("word1")
        widget:forgotFromDict("word1")

        widget:onSwipe(nil, { direction = "west" })
        widget:onSwipe(nil, { direction = "east" })
        widget:onSwipe(nil, { direction = "north" })
        assert.is_false(widget:onSwipe(nil, { direction = "diagonal" }))

        widget:onMultiSwipe(
          nil,
          { multiswipe_directions = "east south west north" }
        )
        widget:onMultiSwipe(nil, { multiswipe_directions = "other" })

        assert.is_true(widget:onCancel())
        assert.is_nil(widget:onReturn())
      end
    )
  end)
end)
