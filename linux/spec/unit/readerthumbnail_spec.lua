describe("ReaderThumbnail module", function()
  local ReaderThumbnail, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize thumbnail module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local thumbnail = readerui.thumbnail
    assert.is_table(thumbnail)

    readerui:onExit()
    readerui:onClose()
  end)
end)
