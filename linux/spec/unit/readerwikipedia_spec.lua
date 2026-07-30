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
    ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize wikipedia module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local wikipedia = readerui.wikipedia
    assert.is_table(wikipedia)

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Menu & Action Registration", function()
    it("should populate main menu items", function()
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
