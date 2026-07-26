describe("ReaderCropping module", function()
  local ReaderCropping, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderCropping = require("apps/reader/modules/readercropping")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize cropping module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local cropping = readerui.cropping or ReaderCropping:new({ ui = readerui })
    assert.is_table(cropping)

    readerui:onExit()
    readerui:onClose()
  end)
end)
