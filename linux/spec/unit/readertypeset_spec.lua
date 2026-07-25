describe("ReaderTypeset module", function()
  local ReaderTypeset

  setup(function()
    require("commonrequire")
    ReaderTypeset = require("apps/reader/modules/readertypeset")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local register_called = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self_module, _target)
          register_called = true
        end,
      },
      document = {
        is_fb2 = false,
      },
    }

    local typeset = ReaderTypeset:new({
      ui = mock_ui,
    })

    assert.is_not_nil(typeset)
    assert.is_true(register_called)
  end)
end)
