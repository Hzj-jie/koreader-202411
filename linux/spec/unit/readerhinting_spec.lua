describe("ReaderHinting module", function()
  local ReaderHinting

  setup(function()
    require("commonrequire")
    ReaderHinting = require("apps/reader/modules/readerhinting")
  end)

  it("should toggle hinting using self.ui.view.hinting", function()
    local mock_ui = {
      view = {
        hinting = false,
      },
    }

    local hinting = ReaderHinting:new({
      ui = mock_ui,
    })

    assert.is_not_nil(hinting)

    hinting:onSetHinting(true)
    assert.is_true(mock_ui.view.hinting)

    hinting:onDisableHinting()
    assert.are.equal(1, #hinting.hinting_states)
    assert.is_true(hinting.hinting_states[1])
  end)
end)
