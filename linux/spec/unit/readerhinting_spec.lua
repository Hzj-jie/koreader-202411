describe("ReaderHinting module", function()
  local ReaderHinting, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderHinting = require("apps/reader/modules/readerhinting")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize hinting module and handle state transitions", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local readerhinting = readerui.hinting
      or ReaderHinting:new({
        ui = readerui,
        view = readerui.view,
        document = readerui.document,
        zoom = readerui.zooming,
      })
    assert.is_table(readerhinting)

    -- Hinting control
    readerhinting:onSetHinting(true)
    assert.is_true(readerui.view.hinting)

    readerhinting:onHintPage()

    -- Disable and restore hinting stack
    readerhinting:onDisableHinting()
    assert.is_false(readerui.view.hinting)

    readerhinting:onHintPage()

    readerhinting:onRestoreHinting()
    assert.is_true(readerui.view.hinting)

    readerui:onExit()
    readerui:onClose()
  end)
end)
