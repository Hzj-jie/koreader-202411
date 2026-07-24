describe("ReaderThumbnail module", function()
  local ReaderThumbnail

  setup(function()
    require("commonrequire")
    ReaderThumbnail = require("apps/reader/modules/readerthumbnail")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local registered = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(self_menu, target)
          registered = true
        end,
      },
      document = {},
    }

    local thumbnail = ReaderThumbnail:new({
      ui = mock_ui,
    })

    assert.is_not_nil(thumbnail)
    assert.is_true(registered)
  end)
end)
