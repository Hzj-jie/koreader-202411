describe("ReaderFlipping module", function()
  local ReaderFlipping

  setup(function()
    require("commonrequire")
    ReaderFlipping = require("apps/reader/modules/readerflipping")
  end)

  it("should initialize icons and support rolling rendering state widgets", function()
    local mock_ui = {
      rolling = {
        rendering_state = 1,
        RENDERING_STATE = {
          PARTIALLY_RERENDERED = 1,
        },
        cre_top_bar_enabled = false,
      },
    }

    local flipping = ReaderFlipping:new({
      ui = mock_ui,
    })

    assert.is_not_nil(flipping)
    assert.is_not_nil(flipping.flipping_widget)

    local widget = flipping:getRollingRenderingStateIconWidget()
    assert.is_not_nil(widget)
  end)
end)
