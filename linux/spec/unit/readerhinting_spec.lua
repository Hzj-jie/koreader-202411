describe("ReaderHinting module", function()
  local ReaderHinting

  setup(function()
    require("commonrequire")
    ReaderHinting = require("apps/reader/modules/readerhinting")
  end)

  it("should toggle hinting using self.ui.view.hinting", function()
    local mock_ui = {
      view = {
        hinting = false,
      },
    }

    local hinting = ReaderHinting:new({
      ui = mock_ui,
    })

    assert.is_not_nil(hinting)

    hinting:onSetHinting(true)
    assert.is_true(mock_ui.view.hinting)

    hinting:onDisableHinting()
    assert.are.equal(1, #hinting.hinting_states)
    assert.is_true(hinting.hinting_states[1])
  end)
end)

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
