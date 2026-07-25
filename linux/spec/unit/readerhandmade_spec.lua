describe("ReaderHandmade module", function()
  local ReaderHandmade, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderHandmade = require("apps/reader/modules/readerhandmade")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize handmade TOC module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local handmade = readerui.handmade
    assert.is_table(handmade)
    assert.is_boolean(handmade:isHandmadeTocEnabled())

    readerui:onExit()
    readerui:onClose()
  end)
end)
