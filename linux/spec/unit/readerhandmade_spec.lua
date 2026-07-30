describe("ReaderHandmade module", function()
  local ReaderHandmade, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderHandmade = require("apps/reader/modules/readerhandmade")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize handmade TOC module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local handmade = readerui.handmade
    assert.is_table(handmade)
    assert.is_boolean(handmade:isHandmadeTocEnabled())

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Menu Registration & Settings", function()
    it("should populate main menu items", function()
      local mock_ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local handmade = ReaderHandmade:new({
        ui = mock_ui,
      })
      local menu_items = {}
      handmade:addToMainMenu(menu_items)
      assert.is_table(menu_items.handmade_toc)
    end)

    it("should handle dispatcher registration", function()
      local handmade = ReaderHandmade:new({
        ui = {
          menu = {
            registerToMainMenu = function() end,
          },
        },
      })
      if type(handmade.onDispatcherRegisterActions) == "function" then
        handmade:onDispatcherRegisterActions()
      end
    end)
  end)
end)
