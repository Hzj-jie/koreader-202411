describe("ReaderZooming module", function()
  local ReaderZooming, DocumentRegistry, ReaderUI, Screen, Event

  setup(function()
    require("commonrequire")
    ReaderZooming = require("apps/reader/modules/readerzooming")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
    Event = require("ui/event")
  end)

  it("should have correct available zoom modes and mapping tables", function()
    assert.is_table(ReaderZooming.available_zoom_modes)
    assert.are.equal("page", ReaderZooming.zoom_genus_to_mode[4])
    assert.are.equal(4, ReaderZooming.zoom_mode_to_genus["page"])
  end)

  it("should handle zoom mode changes and getter/setter", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local zooming = readerui.zooming
    zooming:setZoomMode("page")
    assert.are.equal("page", zooming.zoom_mode)

    zooming:setZoomMode("contentwidth")
    assert.are.equal("contentwidth", zooming.zoom_mode)

    readerui:onExit()
    readerui:onClose()
  end)
end)
