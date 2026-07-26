describe("ReaderKoptListener module", function()
  local ReaderKoptListener, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize kopt listener module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local readerkoptlistener = readerui.koptlistener
      or ReaderKoptListener:new({ ui = readerui })
    assert.is_table(readerkoptlistener)

    readerui:onExit()
    readerui:onClose()
  end)
end)
