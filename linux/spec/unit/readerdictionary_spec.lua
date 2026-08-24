describe("Readerdictionary module", function()
  local DocumentRegistry, ReaderUI, UIManager, Screen, ReaderDictionary

  setup(function()
    require("commonrequire")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    UIManager = require("ui/uimanager")
    Screen = require("device").screen
    ReaderDictionary = require("apps/reader/modules/readerdictionary")
  end)

  local readerui, rolling, dictionary
  setup(function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })
    rolling = readerui.rolling
    dictionary = readerui.dictionary
  end)

  teardown(function()
    readerui:onExit()
    readerui:onClose()
  end)

  it("should show quick lookup window", function()
    UIManager:quit()
    UIManager:show(readerui)
    rolling:onGotoPage(100)
    dictionary:onLookupWord("test")
    UIManager:scheduleIn(1, function()
      UIManager:close(dictionary.dict_window)
      UIManager:close(readerui)
      ReaderUI.instance = readerui
    end)
    UIManager:run()
    Screen:shot("screenshots/reader_dictionary.png")
  end)

  it("should attempt to deinflect (Japanese) word on lookup", function()
    UIManager:quit()
    UIManager:show(readerui)
    rolling:onGotoPage(100)

    local word = "喋っている"
    local s = spy.on(readerui.languagesupport, "extraDictionaryFormCandidates")

    dictionary:stardictLookup(word)

    assert.spy(s).was_called()
    assert.spy(s).was_called_with(match.is_ref(readerui.languagesupport), word)
    if readerui.languagesupport.plugins["japanese_support"] then
      assert.spy(s).was_returned_with(match.is_not_nil())
    end
    readerui.languagesupport.extraDictionaryFormCandidates:revert()

    UIManager:scheduleIn(1, function()
      UIManager:close(dictionary.dict_window)
      UIManager:close(readerui)
      ReaderUI.instance = readerui
    end)
    UIManager:run()
    Screen:shot("screenshots/reader_dictionary_japanese.png")
  end)

  it(
    "should close dict_window, dictionary_lookup_dialog, and download_window when uimanagedCleanUp is called",
    function()
      local Geom = require("ui/geometry")
      local Widget = require("ui/widget/widget")
      local dummy_dict_window =
        Widget:new({ dimen = Geom:new({ w = 10, h = 10 }) })
      local dummy_lookup_dialog =
        Widget:new({ dimen = Geom:new({ w = 10, h = 10 }) })
      local dummy_download_window =
        Widget:new({ dimen = Geom:new({ w = 10, h = 10 }) })

      dictionary:showWidget(dummy_dict_window)
      dictionary:showWidget(dummy_lookup_dialog)
      dictionary:showWidget(dummy_download_window)

      dictionary.dict_window = dummy_dict_window
      dictionary.dictionary_lookup_dialog = dummy_lookup_dialog
      dictionary.download_window = dummy_download_window

      assert.truthy(dictionary.dict_window)
      assert.truthy(dictionary.dictionary_lookup_dialog)
      assert.truthy(dictionary.download_window)

      assert.truthy(UIManager:isWindowWidget(dummy_dict_window))
      assert.truthy(UIManager:isWindowWidget(dummy_lookup_dialog))
      assert.truthy(UIManager:isWindowWidget(dummy_download_window))

      dictionary:uimanagedCleanUp()

      assert.falsy(dictionary.dict_window)
      assert.falsy(dictionary.dictionary_lookup_dialog)
      assert.falsy(dictionary.download_window)

      assert.falsy(UIManager:isWindowWidget(dummy_dict_window))
      assert.falsy(UIManager:isWindowWidget(dummy_lookup_dialog))
      assert.falsy(UIManager:isWindowWidget(dummy_download_window))
    end
  )

  it("should keep reader open when dict_window is closed", function()
    UIManager:quit()
    UIManager:show(readerui)
    rolling:onGotoPage(100)
    dictionary:onLookupWord("test")

    assert.truthy(UIManager:isWindowWidget(readerui))
    assert.truthy(UIManager:isWindowWidget(dictionary.dict_window))

    UIManager:close(dictionary.dict_window)

    assert.falsy(UIManager:isWindowWidget(dictionary.dict_window))
    assert.truthy(UIManager:isWindowWidget(readerui))

    UIManager:close(readerui)
  end)

  it(
    "should register dispatcher actions and handle settings persistence",
    function()
      if type(dictionary.onDispatcherRegisterActions) == "function" then
        dictionary:onDispatcherRegisterActions()
      end

      if type(dictionary.onReadSettings) == "function" then
        dictionary:onReadSettings(readerui.doc_settings)
      end
      if type(dictionary.onSaveSettings) == "function" then
        dictionary:onSaveSettings()
      end
    end
  )

  it("should handle word cleaning and main menu items", function()
    local cleaned =
      dictionary:cleanSelection("  “Testing”—words!  ", true)
    assert.is_string(cleaned)
    assert.is_truthy(cleaned:find("Testing"))

    local menu_items = {}
    dictionary:addToMainMenu(menu_items)
    assert.is_table(menu_items)
    assert.is_table(menu_items.dictionary_lookup)
  end)

  it(
    "should handle dictionary metadata, markup tidying, and options",
    function()
      local num_dicts = dictionary:getNumberOfDictionaries()
      assert.is_number(num_dicts)

      local ifos = dictionary:_getAvailableIfos()
      assert.is_table(ifos)

      local results = {
        {
          dict = "test_dict",
          definition = "<b>Word</b>: definition <br/> text",
        },
      }
      local tidied = dictionary:_tidyMarkup(results)
      assert.is_table(tidied)

      dictionary:updateSdcvDictNamesOptions()
      if type(dictionary.onTogglePreferredDict) == "function" then
        dictionary:onTogglePreferredDict("dummy_dict")
      end
    end
  )

  describe("Dictionary Dialogs & Link Handling", function()
    it("should handle onShowDictionaryLookup and search submission", function()
      local shown_widget
      local orig_show = UIManager.show
      UIManager.show = function(self, w)
        shown_widget = w
      end

      dictionary:onShowDictionaryLookup()
      assert.is_not_nil(dictionary.dictionary_lookup_dialog)
      assert.is_not_nil(shown_widget)

      local lookup_called_with
      local orig_lookup = dictionary.onLookupWord
      dictionary.onLookupWord = function(self, word, is_sane)
        lookup_called_with = word
      end

      -- Input empty text -> no lookup
      dictionary.dictionary_lookup_dialog._input_widget:setText("")
      dictionary.dictionary_lookup_dialog.buttons[1][2].callback()
      assert.is_nil(lookup_called_with)

      -- Input valid text -> triggers lookup
      dictionary.dictionary_lookup_dialog._input_widget:setText("example")
      dictionary.dictionary_lookup_dialog.buttons[1][2].callback()
      assert.are.equal("example", lookup_called_with)

      dictionary.onLookupWord = orig_lookup
      UIManager.show = orig_show
      dictionary:uimanagedCleanUp()
    end)

    it("should handle onHtmlDictionaryLinkTapped", function()
      local lookup_word
      local orig_stardict = dictionary.stardictLookup
      dictionary.stardictLookup = function(self, word)
        lookup_word = word
      end

      -- Ignore external URLs with other protocols
      dictionary:onHtmlDictionaryLinkTapped(
        "dict",
        { uri = "http://example.com" }
      )
      assert.is_nil(lookup_word)

      -- Handle bword:// protocol
      dictionary:onHtmlDictionaryLinkTapped("dict", {
        uri = "bword://hyperlink",
        x0 = 10,
        y0 = 10,
        x1 = 50,
        y1 = 30,
      })
      assert.are.equal("hyperlink", lookup_word)

      -- Handle plain word link
      dictionary:onHtmlDictionaryLinkTapped("dict", {
        uri = "simpleword",
        x0 = 10,
        y0 = 10,
        x1 = 50,
        y1 = 30,
      })
      assert.are.equal("simpleword", lookup_word)

      dictionary.stardictLookup = orig_stardict
    end)

    it(
      "should handle cleanSelection with various punctuation and formatting",
      function()
        -- Normal clean with sane flag
        assert.are.equal("Hello", dictionary:cleanSelection("Hello", true))
        assert.are.equal(
          "Hello",
          dictionary:cleanSelection("  “Hello”  ", false)
        )
        assert.are.equal(
          "Multiple   words",
          dictionary:cleanSelection("  Multiple   words.  ", false)
        )
        assert.are.equal("word", dictionary:cleanSelection("(word)...", false))
      end
    )

    it("should generate download dictionary menus", function()
      local dl_menu = dictionary:_genDownloadDictionariesMenu()
      assert.is_table(dl_menu)
      assert.truthy(#dl_menu > 0)
    end)
  end)
end)
