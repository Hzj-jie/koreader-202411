describe("ReaderWikipedia module", function()
  local ReaderWikipedia

  setup(function()
    require("commonrequire")
    ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
  end)

  it("should initialize and register to main menu via self.ui.menu", function()
    local registered = false
    local mock_ui = {
      menu = {
        registerToMainMenu = function(_self_menu, _target)
          registered = true
        end,
      },
    }

    local wiki = ReaderWikipedia:new({
      ui = mock_ui,
    })

    assert.is_not_nil(wiki)
    assert.is_true(wiki.is_wiki)
    assert.is_true(registered)
  end)
end)
