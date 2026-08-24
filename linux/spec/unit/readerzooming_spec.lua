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

    -- Combo conversions
    local genus, z_type = zooming:mode_to_combo("page")
    assert.is_number(genus)
    assert.is_number(z_type)
    local recovered_mode = zooming:combo_to_mode(genus, z_type)
    assert.are.equal("page", recovered_mode)

    -- Zoom calculation
    local zoom_val = zooming:getZoom(1)
    assert.is_number(zoom_val)
    assert.truthy(zoom_val > 0)

    -- Number of columns and rows
    local cols = zooming:setNumberOf("columns", 2, nil)
    assert.is_number(cols)
    assert.is_number(zooming:getNumberOf("columns", false))
    local rows = zooming:setNumberOf("rows", 3, 10)
    assert.is_number(rows)
    assert.is_number(zooming:getNumberOf("rows", true))

    -- Pinch and spread gestures
    zooming:onPinch(nil, { scale = 0.8 })
    zooming:onSpread(nil, { scale = 1.2 })

    -- Zoom direction
    zooming:onZoom("in")
    zooming:onZoom("out")

    -- Dispatcher actions
    local actions = zooming:getZoomModeActions()
    assert.is_table(actions)

    -- Settings persistence
    zooming:onSaveSettings()
    zooming:onReadSettings(readerui.doc_settings)

    readerui:onExit()
    readerui:onClose()
  end)
end)
