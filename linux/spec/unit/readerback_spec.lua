describe("ReaderBack module", function()
  local ReaderBack, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderBack = require("apps/reader/modules/readerback")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize back navigation module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerback = readerui.back or ReaderBack:new({ ui = readerui })
    assert.is_table(readerback)

    readerui:onExit()
    readerui:onClose()
  end)
end)
