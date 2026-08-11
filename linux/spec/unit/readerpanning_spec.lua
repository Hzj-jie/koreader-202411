describe("ReaderPanning module", function()
  local ReaderPanning

  setup(function()
    require("commonrequire")
    ReaderPanning = require("apps/reader/modules/readerpanning")
  end)

  it("should handle panning events via self.ui.view:PanningUpdate", function()
    local update_args = nil
    local mock_ui = {
      view = {
        visible_area = { w = 600, h = 800 },
        PanningUpdate = function(_self_view, dx, dy)
          update_args = { dx = dx, dy = dy }
        end,
      },
    }

    local panning = ReaderPanning:new({
      ui = mock_ui,
    })

    assert.is_not_nil(panning)

    local res = panning:onPanning({ 1, 0 })
    assert.is_true(res)
    assert.is_not_nil(update_args)
    assert.are.equal(300, update_args.dx)
    assert.are.equal(0, update_args.dy)
  end)
end)

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
