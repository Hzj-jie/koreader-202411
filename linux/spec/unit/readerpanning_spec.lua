describe("ReaderPanning module", function()
  local ReaderPanning, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderPanning = require("apps/reader/modules/readerpanning")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize panning module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local readerpanning = readerui.panning
      or ReaderPanning:new({ ui = readerui })
    assert.is_table(readerpanning)

    readerui:onExit()
    readerui:onClose()
  end)
end)
