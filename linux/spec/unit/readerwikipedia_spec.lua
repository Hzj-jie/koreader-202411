describe("ReaderWikipedia module", function()
  local ReaderWikipedia, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))
    ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize wikipedia module and manage settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local wikipedia = readerui.wikipedia
    assert.is_table(wikipedia)

    if type(wikipedia.onReadSettings) == "function" then
      wikipedia:onReadSettings(readerui.doc_settings)
    end
    if type(wikipedia.onSaveSettings) == "function" then
      wikipedia:onSaveSettings()
    end

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Menu & Word Handling", function()
    it("should populate main menu items and sanitize input words", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local wiki = ReaderWikipedia:new({
        ui = mock_ui,
      })

      local menu_items = {}
      wiki:addToMainMenu(menu_items)
      assert.is_table(menu_items.wikipedia_lookup)

      if type(wiki.cleanWord) == "function" then
        local cleaned = wiki:cleanWord("  Test Word!  ")
        assert.is_string(cleaned)
      end
    end)

    it("should handle dispatcher registration", function()
      local wiki = ReaderWikipedia:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })
      if type(wiki.onDispatcherRegisterActions) == "function" then
        wiki:onDispatcherRegisterActions()
      end
    end)
  end)

  describe("onLookupWikipedia window stack ordering", function()
    local readerui, ButtonDialog, UIManager
    before_each(function()
      UIManager = require("ui/uimanager")
      ButtonDialog = require("ui/widget/buttondialog")
      local sample_epub = "spec/front/unit/data/leaves.epub"
      readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_epub),
      })
      UIManager:quit()
      UIManager:show(readerui)
    end)
    after_each(function()
      if readerui.wikipedia.dict_window then
        UIManager:close(readerui.wikipedia.dict_window)
      end
      readerui:onExit()
      readerui:onClose()
      UIManager:quit()
    end)

    it(
      "should place Wikipedia DictQuickLookup on top of active modal ButtonDialog",
      function()
        -- Simulate an open modal dialog (like highlight menu)
        local modal_dialog = ButtonDialog:new({
          buttons = {
            {
              {
                text = "Test",
                callback = function() end,
              },
            },
          },
        })
        UIManager:show(modal_dialog)
        assert.is_true(modal_dialog.modal)

        local modal_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == modal_dialog then
            modal_index = idx
            break
          end
        end
        assert.is_not_nil(modal_index)

        -- Mock NetworkMgr to run immediately in test environment
        local NetworkMgr = require("ui/network/manager")
        local orig_runWhenOnline = NetworkMgr.runWhenOnline
        NetworkMgr.runWhenOnline = function(_, cb)
          cb()
          return true
        end

        -- Mock Wikipedia API to return fake search results immediately
        local Wikipedia = require("ui/wikipedia")
        local orig_search = Wikipedia.searchAndGetIntros
        Wikipedia.searchAndGetIntros = function()
          return {
            {
              title = "Test",
              extract = "Test extract",
              pageid = 1,
              length = 500,
            },
          }
        end

        -- Trigger lookup
        readerui.wikipedia:onLookupWikipedia("Test", true)

        assert.is_not_nil(readerui.wikipedia.dict_window)
        local wiki_index = nil
        for idx, win in ipairs(UIManager._window_stack) do
          if win.widget == readerui.wikipedia.dict_window then
            wiki_index = idx
            break
          end
        end
        assert.is_not_nil(wiki_index)

        -- Wikipedia lookup window MUST be layered above the modal dialog
        assert.is_true(wiki_index > modal_index)

        Wikipedia.searchAndGetIntros = orig_search
        NetworkMgr.runWhenOnline = orig_runWhenOnline
        UIManager:close(modal_dialog)
      end
    )
  end)
end)
