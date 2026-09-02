describe("Readersearch module", function()
  local sample_epub = "spec/front/unit/data/juliet.epub"
  local sample_pdf = "spec/front/unit/data/sample.pdf"
  local DocumentRegistry, ReaderUI, Screen, dbg

  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    dbg = require("dbg")
  end)

  describe("search API for EPUB documents", function()
    local readerui, doc, search, rolling
    setup(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      doc = readerui.document
      search = readerui.search
      rolling = readerui.rolling
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    it("should search backward", function()
      rolling:onGotoPage(10)
      assert.truthy(search:searchFromCurrent("Verona", 1))
      for i = 1, 100, 10 do
        rolling:onGotoPage(i)
        local words = search:searchFromCurrent("Verona", 1)
        if words then
          for _, word in ipairs(words) do
            local pageno = doc:getPageFromXPointer(word.start)
            assert.truthy(pageno <= i)
          end
        end
      end
    end)
    it("should search forward", function()
      rolling:onGotoPage(10)
      assert.truthy(search:searchFromCurrent("Verona", 0))
      for i = 1, 100, 10 do
        rolling:onGotoPage(i)
        local words = search:searchFromCurrent("Verona", 0)
        if words then
          for _, word in ipairs(words) do
            local pageno = doc:getPageFromXPointer(word.start)
            assert.truthy(pageno >= i)
          end
        end
      end
    end)
    it("should find the first occurrence", function()
      for i = 10, 100, 10 do
        rolling:onGotoPage(i)
        local words = search:searchFromStart("Verona")
        assert.truthy(words)
        local pageno = doc:getPageFromXPointer(words[1].start)
        assert.truthy(pageno < 10)
      end
      for i = 1, 5, 1 do
        rolling:onGotoPage(i)
        local words = search:searchFromStart("Verona")
        assert(words == nil)
      end
    end)
    it("should find the last occurrence", function()
      for i = 100, 180, 10 do
        rolling:onGotoPage(i)
        local words = search:searchFromEnd("Verona")
        assert.truthy(words)
        local pageno = doc:getPageFromXPointer(words[1].start)
        assert.truthy(pageno > 185)
      end
      for i = 290, 335, 1 do
        rolling:onGotoPage(i)
        local words = search:searchFromEnd("Verona")
        assert(words == nil)
      end
    end)
    it("should find all occurrences", function()
      local count = 0
      rolling:onGotoPage(1)
      local cur_page = doc:getCurrentPage()
      local words = search:searchFromCurrent("Verona", 0)
      while words do
        local new_page = nil
        for _, word in ipairs(words) do
          local word_page = doc:getPageFromXPointer(word.start)
          if word_page ~= cur_page then
            if not new_page then
              new_page = word_page
              count = count + 1
              doc:gotoXPointer(word.start)
            else
              if word_page == new_page then
                count = count + 1
              end
            end
          end
        end
        if not new_page then
          break
        end
        cur_page = doc:getCurrentPage()
        words = search:searchNext("Verona", 0)
      end
      assert.are.equal(13, count)
    end)
  end)

  describe("search API for PDF documents", function()
    local readerui, doc, search, paging
    setup(function()
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })
      doc = readerui.document
      search = readerui.search
      paging = readerui.paging
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)
    it(
      "should match single word with case insensitive option in one page",
      function()
        assert.are.equal(
          9,
          #doc.koptinterface:findAllMatches(doc, "what", true, 20)
        )
        assert.are.equal(
          51,
          #doc.koptinterface:findAllMatches(doc, "the", true, 20)
        )
        assert.are.equal(
          0,
          #doc.koptinterface:findAllMatches(doc, "xxxx", true, 20)
        )
      end
    )
    it(
      "should match single word with case sensitive option in one page",
      function()
        assert.are.equal(
          7,
          #doc.koptinterface:findAllMatches(doc, "what", false, 20)
        )
        assert.are.equal(
          49,
          #doc.koptinterface:findAllMatches(doc, "the", false, 20)
        )
        assert.are.equal(
          0,
          #doc.koptinterface:findAllMatches(doc, "xxxx", false, 20)
        )
      end
    )
    it("should match phrase in one page", function()
      assert.are.equal(
        2 * 2,
        #doc.koptinterface:findAllMatches(doc, "mean that", true, 20)
      )
    end)
    it("should match whole phrase in one page", function()
      assert.are.equal(
        1 * 3,
        #doc.koptinterface:findAllMatches(doc, "mean that the", true, 20)
      )
    end)
    it("should not match empty string", function()
      assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "", true, 1))
    end)
    it("should not match on page without text layer", function()
      assert.are.equal(0, #doc.koptinterface:findAllMatches(doc, "e", true, 1))
    end)
    it("should search backward", function()
      paging:onGotoPage(20)
      assert.truthy(search:searchFromCurrent("test", 1))
      for i = 1, 40, 10 do
        paging:onGotoPage(i)
        local words = search:searchFromCurrent("test", 1)
        if words then
          assert.truthy(words.page <= i)
        end
      end
    end)
    it("should search forward", function()
      paging:onGotoPage(20)
      assert.truthy(search:searchFromCurrent("test", 0))
      for i = 1, 40, 10 do
        paging:onGotoPage(i)
        local words = search:searchFromCurrent("test", 0)
        if words then
          assert.truthy(words.page >= i)
        end
      end
    end)
    it("should find the first occurrence", function()
      for i = 20, 40, 10 do
        paging:onGotoPage(i)
        local words = search:searchFromStart("test")
        assert.truthy(words)
        assert.are.equal(10, words.page)
      end
      for i = 1, 10, 2 do
        paging:onGotoPage(i)
        local words = search:searchFromStart("test")
        assert(words == nil)
      end
    end)
    it("should find the last occurrence", function()
      for i = 10, 30, 10 do
        paging:onGotoPage(i)
        local words = search:searchFromEnd("test")
        assert.truthy(words)
        assert.are.equal(32, words.page)
      end
      for i = 40, 50, 2 do
        paging:onGotoPage(i)
        local words = search:searchFromEnd("test")
        assert(words == nil)
      end
    end)
    it("should find all occurrences", function()
      local count = 0
      paging:onGotoPage(1)
      local words = search:searchFromCurrent("test", 0)
      while words do
        count = count + #words
        paging:onGotoPage(words.page)
        words = search:searchNext("test", 0)
      end
      assert.are.equal(11, count)
    end)
  end)

  describe("uimanagedCleanUp", function()
    it(
      "closes input_dialog, search_dialog, and result_menu automatically",
      function()
        local ReaderSearch = require("apps/reader/modules/readersearch")
        local mock_menu_inst = {
          registerToMainMenu = spy.new(function() end),
        }
        local rs = ReaderSearch:new({ ui = { menu = mock_menu_inst } })
        local UIManager = require("ui/uimanager")

        local original_show = UIManager.show
        local original_closeIfShown = UIManager.closeIfShown

        local closeIfShown_calls = {}
        UIManager.show = function() end
        UIManager.closeIfShown = function(self, widget)
          table.insert(closeIfShown_calls, widget)
        end

        local dummy_input = { name = "dummy_input" }
        local dummy_search = { name = "dummy_search" }
        local dummy_result = { name = "dummy_result" }

        rs:showWidget(dummy_input)
        rs:showWidget(dummy_search)
        rs:showWidget(dummy_result)

        rs.input_dialog = dummy_input
        rs.search_dialog = dummy_search
        rs.result_menu = dummy_result

        rs:uimanagedCleanUp()

        assert.is_nil(rs.input_dialog)
        assert.is_nil(rs.search_dialog)
        assert.is_nil(rs.result_menu)

        assert.same(
          { dummy_input, dummy_search, dummy_result },
          closeIfShown_calls
        )

        UIManager.show = original_show
        UIManager.closeIfShown = original_closeIfShown
      end
    )

    it("should verify readersearch module and main menu items", function()
      local ReaderSearch = require("apps/reader/modules/readersearch")
      assert.is_table(ReaderSearch)

      local rs = ReaderSearch:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
          document = {
            info = { has_crengine = true },
            search = function()
              return {}
            end,
            getAndClearRegexSearchError = function()
              return nil
            end,
          },
        },
      })
      local menu_items = {}
      rs:addToMainMenu(menu_items)
      assert.is_table(menu_items.fulltext_search_settings)

      if type(rs.onFulltextSearchSettings) == "function" then
        rs:onFulltextSearchSettings()
      end

      if type(rs.onDispatcherRegisterActions) == "function" then
        rs:onDispatcherRegisterActions()
      end

      rs:showErrorNotification(0, false, 100)
      rs:showErrorNotification(0, true, 100)
      rs:showErrorNotification(150, false, 100)
    end)
  end)

  describe("ReaderSearch UI & Dialog Workflows", function()
    local readerui, doc, search, rolling, UIManager
    setup(function()
      UIManager = require("ui/uimanager")
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      doc = readerui.document
      search = readerui.search
      rolling = readerui.rolling
    end)
    teardown(function()
      readerui:onExit()
      readerui:onClose()
    end)

    it("should handle onShowFulltextSearchInput and input callback", function()
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      search:onShowFulltextSearchInput("Verona")
      assert.is_not_nil(search.input_dialog)
      assert.is_not_nil(shown_widget)

      -- Trigger forward button callback
      local orig_search_cb = search.searchCallback
      local cb_called = false
      search.searchCallback = function(self, reverse, text)
        cb_called = true
        assert.are.equal(0, reverse)
      end

      search.input_dialog.buttons[1][4].callback()
      assert.is_true(cb_called)

      search.searchCallback = orig_search_cb
      UIManager.show = orig_show
      search:uimanagedCleanUp()
    end)

    it("should handle searchCallback and update search_dialog", function()
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      rolling:onGotoPage(10)
      search:searchCallback(0, "Verona")
      assert.is_not_nil(search.search_dialog)

      -- Search next backward and forward
      search:searchCallback(1, "Verona")
      assert.is_not_nil(search.search_dialog)

      -- Search non-existent text
      search:searchCallback(0, "NON_EXISTENT_STRING_XYZ")

      UIManager.show = orig_show
      search:uimanagedCleanUp()
    end)

    it("should handle searchText from highlight selection", function()
      local orig_search_cb = search.searchCallback
      local cb_text
      search.searchCallback = function(self, reverse, text)
        cb_text = text
      end

      search:searchText("selected text")
      assert.are.equal("selected text", cb_text)
      search.searchCallback = orig_search_cb
    end)

    it("should handle findAllText and onShowFindAllResults menu", function()
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      search:findAllText("Verona")
      assert.is_table(search.findall_results)
      assert.truthy(#search.findall_results > 0)

      search:onShowFindAllResults()
      assert.is_not_nil(search.result_menu)

      -- Test result menu item selection callback
      local first_item = search.result_menu.item_table[1]
      assert.is_not_nil(first_item)
      if first_item.callback then
        first_item.callback()
      end

      -- Test showAllResultsMenuDialog
      search:showAllResultsMenuDialog()
      assert.is_not_nil(shown_widget)

      -- Close and clean up
      UIManager.show = orig_show
      search:uimanagedCleanUp()
    end)

    it("should handle main menu settings callbacks and spin widgets", function()
      local menu_items = {}
      search:addToMainMenu(menu_items)
      assert.is_table(menu_items.fulltext_search_settings)

      local settings = menu_items.fulltext_search_settings.sub_item_table
      assert.is_table(settings)

      local shown_widgets = {}
      local orig_show = search.showWidget
      search.showWidget = function(self, w)
        table.insert(shown_widgets, w)
      end

      local mock_menu = { updateItems = function() end }

      for _, item in ipairs(settings) do
        if item.text_func then
          item.text_func()
        end
        if item.enabled_func then
          item.enabled_func()
        end
        if item.checked_func then
          item.checked_func()
        end
        if item.callback then
          item.callback(mock_menu)
        end
      end

      for _, w in ipairs(shown_widgets) do
        if w.callback then
          pcall(w.callback, { value = 6 })
        end
        if w.extra_callback then
          pcall(w.extra_callback)
        end
      end

      search.showWidget = orig_show
    end)

    it("should handle regex checking and invalid regex error display", function()
      search.use_regex = true
      doc.checkRegex = function(_, pat)
        if pat == "[unclosed" then
          return 100 -- regex error code
        end
        return nil
      end

      local shown_msg
      search.showWidget = function(self, w)
        shown_msg = w
      end

      search:onShowFulltextSearchInput("[unclosed")
      search.check_button_regex = { checked = true }
      search.check_button_case = { checked = false }

      -- Trigger forward search button callback with invalid regex
      search.input_dialog.buttons[1][4].callback()
      assert.is_not_nil(shown_msg)

      search:uimanagedCleanUp()
    end)

    it("should handle search dialog tap_close_callback and dirty UI update", function()
      local highlight_cleared = false
      local orig_clear = search.ui.highlight.clear
      search.ui.highlight.clear = function(self)
        highlight_cleared = true
      end

      local dirty_called = false
      local orig_setDirty = UIManager.setDirty
      UIManager.setDirty = function(self, target, mode)
        dirty_called = true
        return orig_setDirty(self, target, mode)
      end

      search:onShowFulltextSearchInput("Sample")
      search.check_button_regex = { checked = false }
      search.check_button_case = { checked = false }

      -- Trigger forward search button callback
      local fwd_btn = search.input_dialog.buttons[1][4]
      fwd_btn.callback()

      if search.search_dialog and search.search_dialog.tap_close_callback then
        search.search_dialog.tap_close_callback()
        assert.is_true(highlight_cleared)
        assert.is_true(dirty_called)
      end

      search.ui.highlight.clear = orig_clear
      UIManager.setDirty = orig_setDirty
      search:uimanagedCleanUp()
    end)
  end)
end)

