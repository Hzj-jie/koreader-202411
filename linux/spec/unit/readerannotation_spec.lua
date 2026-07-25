describe("ReaderAnnotation module", function()
  local ReaderAnnotation, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderAnnotation = require("apps/reader/modules/readerannotation")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize annotation module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local annotation = readerui.annotation
    assert.is_table(annotation)

    readerui:onExit()
    readerui:onClose()
  end)
end)
