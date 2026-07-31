describe("ReaderCropping module", function()
  local ReaderCropping, DocumentRegistry, ReaderUI, Screen

  setup(function()
    require("commonrequire")
    package.unloadAll()
    require("document/canvascontext"):init(require("device"))

    ReaderCropping = require("apps/reader/modules/readercropping")
    DocumentRegistry = require("document/documentregistry")
    ReaderUI = require("apps/reader/readerui")
    Screen = require("device").screen
  end)

  it("should initialize cropping module", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local cropping = readerui.cropping or ReaderCropping:new({ ui = readerui })
    assert.is_table(cropping)

    readerui:onExit()
    readerui:onClose()
  end)

  it("should read and save bbox settings", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local cropping = ReaderCropping:new({
      ui = readerui,
      document = readerui.document,
    })

    local mock_config = {
      readTable = function(self, key)
        if key == "bbox" then return { [1] = { 0, 0, 100, 100 } } end
      end,
    }

    cropping:onReadSettings(mock_config)
    assert.is_table(cropping.document.bbox)
    assert.is_table(cropping.document.bbox[1])

    cropping:onSaveSettings()

    readerui:onExit()
    readerui:onClose()
  end)

  it("should handle zoom mode transitions for cropping", function()
    local sample_pdf = "spec/front/unit/data/sample.pdf"
    local readerui = ReaderUI:new({
      dimen = Screen:getSize(),
      document = DocumentRegistry:openDocument(sample_pdf),
    })

    local cropping = ReaderCropping:new({
      ui = readerui,
      document = readerui.document,
      orig_zoom_mode = "page",
      setZoomMode = function(self, mode) end,
    })

    cropping:setCropZoomMode(true)
    cropping:setCropZoomMode(false)

    readerui:onExit()
    readerui:onClose()
  end)
end)
