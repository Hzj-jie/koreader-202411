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
end)
