describe("ReaderTypeset module", function()
  local ReaderTypeset, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize typeset module and handle settings", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local typeset = readerui.typeset
    assert.is_table(typeset)

    readerui:onExit()
    readerui:onClose()
  end)
end)
