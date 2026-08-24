describe("ReaderKoptListener module", function()
  local ReaderKoptListener, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderKoptListener = require("apps/reader/modules/readerkoptlistener")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize kopt listener module and handle events", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local readerkoptlistener = readerui.koptlistener
      or ReaderKoptListener:new({
        ui = readerui,
        document = readerui.document,
        view = readerui.view,
      })
    assert.is_table(readerkoptlistener)

    -- Zoom mode handling
    readerkoptlistener:setZoomMode("contentwidth")
    readerkoptlistener:onSetZoomMode("page", "external")
    assert.are.equal("page", readerkoptlistener.normal_zoom_mode)
    readerkoptlistener:onRestoreZoomMode()

    -- Font size fine tuning
    local orig_font_size = readerui.document.configurable.font_size or 1.0
    readerkoptlistener:onFineTuningFontSize(0.1)
    assert.is_near(
      orig_font_size + 0.1,
      readerui.document.configurable.font_size,
      0.001
    )

    -- Zoom update
    readerkoptlistener:onZoomUpdate(1.5)

    -- Doc lang update
    readerkoptlistener:onDocLangUpdate("chi_sim")
    readerkoptlistener:onDocLangUpdate("eng")

    -- Config change
    readerkoptlistener:onConfigChange("contrast", 1.2)
    assert.are.equal(1.2, readerui.document.configurable.contrast)

    -- Settings persistence
    readerkoptlistener:onSaveSettings()
    readerkoptlistener:onReadSettings(readerui.doc_settings)

    readerui:onExit()
    readerui:onClose()
  end)
end)
