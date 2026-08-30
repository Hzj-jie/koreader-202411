describe("ReaderPanning module", function()
  local ReaderPanning, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    ReaderPanning = require("apps/reader/modules/readerpanning")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it(
    "should initialize panning module and handle panning operations",
    function()
      local sample_pdf = "spec/front/unit/data/sample.pdf"
      local readerui = ReaderUI:new({
        dimen = Screen:getSize(),
        document = DocumentRegistry:openDocument(sample_pdf),
      })

      local readerpanning = readerui.panning
        or ReaderPanning:new({ ui = readerui, view = readerui.view })
      assert.is_table(readerpanning)

      -- Test onPanning in 4 directions
      readerpanning:onPanning({ 1, 0 })
      readerpanning:onPanning({ -1, 0 })
      readerpanning:onPanning({ 0, 1 })
      readerpanning:onPanning({ 0, -1 })

      -- Test key events registration & connection
      readerpanning:registerKeyEvents()
      readerpanning:onPhysicalKeyboardConnected()
      readerpanning:onGesture()

      readerui:onExit()
      readerui:onClose()
    end
  )
end)
