describe("ReaderStatus module", function()
  local ReaderStatus, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderStatus = require("apps/reader/modules/readerstatus")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize status module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local status = readerui.status
    assert.is_table(status)

    readerui:onExit()
    readerui:onClose()
  end)
end)
