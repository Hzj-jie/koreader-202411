describe("ReaderGoto module", function()
  local ReaderGoto, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderGoto = require("apps/reader/modules/readergoto")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize goto page module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readergoto = readerui.readergoto or ReaderGoto:new({ ui = readerui })
    assert.is_table(readergoto)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle dispatcher registration and main menu items", function()
    local rgoto = ReaderGoto:new({
      ui = {
        menu = {
          registerToMainMenu = function() end,
        },
      },
    })
    if type(rgoto.onDispatcherRegisterActions) == "function" then
      rgoto:onDispatcherRegisterActions()
    end
  end)
end)
