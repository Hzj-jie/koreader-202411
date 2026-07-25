describe("ReaderHinting module", function()
  local ReaderHinting, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderHinting = require("apps/reader/modules/readerhinting")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize hinting module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerhinting = readerui.hinting or ReaderHinting:new({ ui = readerui })
    assert.is_table(readerhinting)

    readerui:onExit()
    readerui:onClose()
  end)
end)
