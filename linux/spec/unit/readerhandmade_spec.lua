describe("ReaderHandmade module", function()
  local ReaderHandmade, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderHandmade = require("apps/reader/modules/readerhandmade")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize handmade TOC module and read/save settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local handmade = readerui.handmade
    assert.is_table(handmade)

    handmade:onReadSettings(readerui.doc_settings)
    assert.is_boolean(handmade:isHandmadeTocEnabled())
    assert.is_boolean(handmade:isHandmadeTocEditEnabled())

    handmade:onSaveSettings()

    readerui:onExit()
    readerui:onClose()
  end)

  it("should manage custom TOC items", function()
    local mock_ui = {
      menu = { registerToMainMenu = function() end },
      doc_settings = {
        isTrue = function() return false end,
        nilOrTrue = function() return true end,
        readTableRef = function() return {} end,
        save = function() end,
        delete = function() end,
      },
    }
    local handmade = ReaderHandmade:new({ ui = mock_ui })
    handmade:onReadSettings(mock_ui.doc_settings)

    assert.is_table(handmade.toc)
    table.insert(handmade.toc, { title = "Chapter 1", page = 5 })

    assert.are.equal(1, #handmade.toc)

    if handmade.clearHandmadeToc then
      handmade:clearHandmadeToc()
      assert.are.equal(0, #handmade.toc)
    end
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
  end)
end)
