describe("ReaderConfig module", function()
  local ReaderConfig, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderConfig = require("apps/reader/modules/readerconfig")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize config module", function()
    local sample_epub = "spec/front/unit/data/leaves.epub"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_epub),
    })

    local readerconfig = readerui.config or ReaderConfig:new({ ui = readerui })
    assert.is_table(readerconfig)

    readerui:onExit()
    readerui:onClose()
  end)
end)
