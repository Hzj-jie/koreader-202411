describe("ReaderZooming module", function()
  local ReaderZooming

  setup(function()
    require("commonrequire")
    ReaderZooming = require("apps/reader/modules/readerzooming")
  end)

  it("should convert zoom modes and combos correctly", function()
    local mock_ui = {}
    local zooming = ReaderZooming:new({
      ui = mock_ui,
    })

    assert.is_not_nil(zooming)

    -- Test mode_to_combo
    local genus, ztype = zooming:mode_to_combo("pagewidth")
    assert.is_not_nil(genus)
    assert.is_not_nil(ztype)

    -- Test combo_to_mode
    local mode = zooming:combo_to_mode(genus, ztype)
    assert.are.equal("pagewidth", mode)
  end)
end)

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

  it("should set zoom modes and convert zoom mode combos", function()
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

    local genus, z_type = zooming:mode_to_combo("page")
    assert.is_number(genus)
    assert.is_number(z_type)
    local recovered_mode = zooming:combo_to_mode(genus, z_type)
    assert.are.equal("page", recovered_mode)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should calculate zoom and configure columns and rows", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local zooming = readerui.zooming
    local zoom_val = zooming:getZoom(1)
    assert.is_number(zoom_val)
    assert.truthy(zoom_val > 0)

    local cols = zooming:setNumberOf("columns", 2, nil)
    assert.is_number(cols)
    assert.is_number(zooming:getNumberOf("columns", false))
    local rows = zooming:setNumberOf("rows", 3, 10)
    assert.is_number(rows)
    assert.is_number(zooming:getNumberOf("rows", true))

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle pinch, spread, zoom in/out, and zoom callbacks", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local zooming = readerui.zooming
    zooming:onPinch(nil, { scale = 0.8 })
    zooming:onSpread(nil, { scale = 1.2 })

    zooming:onZoom("in")
    zooming:onZoom("out")

    local actions = zooming:getZoomModeActions()
    assert.is_table(actions)

    local modes = { "contentwidth", "contentheight", "content", "page", "pagewidth", "pageheight", "free", "columns", "rows" }
    for _, m in ipairs(modes) do
      local cb = zooming:genSetZoomModeCallBack(m)
      assert.is_function(cb)
      cb()
    end

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle free zoom, rotation updates, define zoom, and settings persistence", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local zooming = readerui.zooming
    zooming:setZoomMode("page")
    zooming:onToggleFreeZoom(nil, { pos = { x = 200, y = 200 } })
    zooming:onToggleFreeZoom(nil, { pos = { x = 200, y = 200 } })

    zooming:onRotationUpdate(90)
    zooming:onRotationUpdate(0)

    zooming:onDefineZoom("columns")
    zooming:onDefineZoom("rows")
    zooming:onDefineZoom("manual")
    zooming:onDefineZoom("set_zoom_overlap_h")
    zooming:onDefineZoom("set_zoom_overlap_v")

    zooming:onSaveSettings()
    zooming:onReadSettings(readerui.doc_settings)

    -- Test oversized bbox triggering onBBoxUpdate(nil)
    local bbox_updated = false
    readerui.view.onBBoxUpdate = function(self, bbox)
      if bbox == nil then
        bbox_updated = true
      end
    end
    local orig_getUsedBBox = readerui.document.getUsedBBoxDimensions
    readerui.document.getUsedBBoxDimensions = function()
      return { x = 0, y = 0, w = 99999, h = 99999 }
    end
    zooming:setZoomMode("contentwidth")
    zooming:getZoom(1)
    assert.is_true(bbox_updated)
    readerui.document.getUsedBBoxDimensions = orig_getUsedBBox

    readerui:onExit()
    readerui:onClose()
  end)
end)

