describe("ReaderDogear module", function()
  local ReaderDogear, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderDogear = require("apps/reader/modules/readerdogear")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize dogear module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerdogear = readerui.dogear or ReaderDogear:new({ ui = readerui })
    assert.is_table(readerdogear)

    readerui:onExit()
    readerui:onClose()
  end)
end)
