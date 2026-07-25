describe("ReaderFlipping module", function()
  local ReaderFlipping, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderFlipping = require("apps/reader/modules/readerflipping")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize flipping module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerflipping = readerui.flipping or ReaderFlipping:new({ ui = readerui })
    assert.is_table(readerflipping)

    readerui:onExit()
    readerui:onClose()
  end)
end)
