describe("ReaderCropping module", function()
  local ReaderCropping

  setup(function()
    require("commonrequire")
    ReaderCropping = require("apps/reader/modules/readercropping")
  end)

  it("should backup and restore view dimensions using self.ui.view:getSize()", function()
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
  end)
end)
