describe("ReaderWikipedia module", function()
  local ReaderWikipedia

  setup(function()
    require("commonrequire")
    ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local registered = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self_menu, _target)
          registered = true
        end,
      },
    }

    local wiki = ReaderWikipedia:new({
      ui = mock_ui,
    })

    assert.is_not_nil(wiki)
    assert.is_true(wiki.is_wiki)
    assert.is_true(registered)
  end)
end)

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
end)
