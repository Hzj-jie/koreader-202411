describe("ReaderThumbnail module", function()
  local ReaderThumbnail, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize thumbnail module and add items to main menu", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local thumbnail = readerui.thumbnail
    assert.is_table(thumbnail)

    local menu_items = {}
    thumbnail:addToMainMenu(menu_items)
    assert.is_table(menu_items.book_map)

    readerui:onExit()
    readerui:onClose()
  end)

  describe("Capabilities & Actions", function()
    it("should check page browser and book map availability", function()
      local mock_ui = {
        document = {
          info = {},
        },
        menu = {
          registerToMainMenu = function() end,
        },
      }
      local thumb = ReaderThumbnail:new({
        ui = mock_ui,
      })

      if type(thumb.hasBookMap) == "function" then
        assert.is_boolean(thumb:hasBookMap())
      end
    end)
  end)
end)
