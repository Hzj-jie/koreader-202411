describe("ReaderPageMap module", function()
  local ReaderPageMap, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderPageMap = require("apps/reader/modules/readerpagemap")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize pagemap module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local pagemap = readerui.pagemap
    assert.is_table(pagemap)

    readerui:onExit()
    readerui:onClose()
  end)
end)
