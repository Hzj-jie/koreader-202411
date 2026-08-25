describe("ReaderCropping module", function()
  local ReaderCropping

  setup(function()
    require("commonrequire")
    ReaderCropping = require("apps/reader/modules/readercropping")
  end)

  it(
    "should backup and restore view dimensions using self.ui.view:getSize()",
    function()
      local mock_ui = {
        view = {
          zoom_mode = "page",
          outer_page_color = 0,
          footer_visible = true,
          getSize = function()
            return { w = 600, h = 800 }
          end,
        },
        document = {
          configurable = { text_wrap = 0 },
        },
      }

      local cropping = ReaderCropping:new({
        ui = mock_ui,
        document = {
          configurable = { text_wrap = 0 },
        },
      })

      assert.is_not_nil(cropping)

      cropping:onPageCrop("auto")
      assert.are.equal("page", cropping.orig_zoom_mode)
    end
  )
end)

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
        if key == "bbox" then
          return { [1] = { x0 = 0, y0 = 0, x1 = 100, y1 = 100 } }
        end
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
      view = readerui.view,
      orig_zoom_mode = "page",
      setZoomMode = function(self, mode) end,
    })

    cropping:setCropZoomMode(true)
    cropping:setCropZoomMode(false)

    -- Test page crop modes
    cropping:onPageCrop("none")
    cropping:onPageCrop("auto")

    -- Test interactive crop session
    cropping:onPageCrop("semi-auto")
    assert.truthy(cropping.crop_dialog)
    cropping.bbox_widget.screen_bbox =
      cropping.bbox_widget:getScreenBBox(cropping.bbox_widget.page_bbox)

    -- Test confirm crop
    cropping:onConfirmPageCrop()

    -- Test cancel crop
    cropping:onPageCrop("semi-auto")
    cropping:onCancelPageCrop()

    readerui:onExit()
    readerui:onClose()
  end)
end)
